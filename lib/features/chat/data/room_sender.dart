import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/best_effort.dart';
import '../../../core/errors/caught_errors.dart';
import '../../../core/errors/connection_error.dart';
import '../../../core/errors/global_error_handler.dart';
import '../../../core/files/file_system.dart';
import '../../../core/files/picked_file.dart';
import '../../../core/l10n/display_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/currently_open_room_provider.dart';
import '../../../core/matrix/image_send_preparation.dart';
import '../../../core/matrix/media_gallery_group.dart';
import '../../../core/matrix/media_processing_exception.dart';
import '../../../core/matrix/media_size.dart';
import '../../../core/matrix/room_media_feed.dart';
import '../../../core/matrix/send_failure.dart';
import '../../../core/matrix/send_progress.dart';
import '../../../core/matrix/upload_foreground_service.dart';
import '../../../core/matrix/upload_http_client.dart';
import '../../../core/matrix/video_send_preparation.dart';
import '../../../core/settings/app_preferences_provider.dart';
import '../../../core/ui/notice.dart';
import 'composed_media.dart';
import 'discarded_sends.dart';
import 'forward_uploads.dart';
import 'forwarding.dart';
import 'pending_attachment_send.dart';
import 'unsent_events.dart';

final roomSenderProvider = Provider.family<RoomSender, Room>((ref, room) {
  final container = ref.container;
  final sender = RoomSender(
    room: room,
    discarded: ref.watch(discardedSendsProvider),
    reduceMediaSize: () => container.read(reduceMediaSizeProvider),
    chatOpen: () => container.read(currentlyOpenRoomIdProvider) == room.id,
    say: (message) => globalScaffoldMessengerKey.currentState?.say(message),
  );
  ref.onDispose(sender.dispose);
  return sender;
});

class ForwardNotSent implements Exception {
  const ForwardNotSent();

  @override
  String toString() => 'ForwardNotSent';
}

class RoomSender extends ChangeNotifier {
  RoomSender({
    required this.room,
    required this._discarded,
    required this._reduceMediaSize,
    required this._chatOpen,
    required this._say,
  });

  final Room room;
  final DiscardedSends _discarded;
  final bool Function() _reduceMediaSize;
  final bool Function() _chatOpen;
  final void Function(String message) _say;

  final _pending = ValueNotifier<PendingAttachmentSend?>(null);
  final List<FailedMediaSend> _failed = [];
  final _copies = <String>{};
  final _copyUses = <String, int>{};
  final _sends = <String, SendScope>{};
  bool _disposed = false;

  ValueListenable<PendingAttachmentSend?> get pending => _pending;

  late final List<FailedMediaSend> failed = UnmodifiableListView(_failed);

  AppLocalizations get _l10n => deviceLocalizations();

  void _sayFailed(Object? error, @displayText String failed) =>
      _say(failureMessage(_l10n, error, failed: failed));

  Future<void> sendText(
    String text, {
    Event? editing,
    Event? replyingTo,
  }) async {
    await runBestEffort(
      () => SendScope().run(
        () => room.sendTextEvent(
          text,
          editEventId: editing?.eventId,
          inReplyTo: replyingTo,
          parseMarkdown: false,
          parseCommands: false,
        ),
      ),
      label: 'send a text message',
    );
  }

  Future<Object?> forward(List<Event> items, {ForwardUploads? uploads}) async {
    final shared = uploads ?? ForwardUploads();
    Future<List<Object?>> sendAll() => _sendAsGallery(
      items,
      (item, gallery) => _forwardItem(
        item,
        gallery: gallery,
        uploads: shared,
        announce: false,
      ),
    );
    final failures = items.any((item) => forwardNeedsUpload(item, room))
        ? await _keepingUploadAlive(sendAll)
        : await sendAll();
    return failures.nonNulls.firstOrNull;
  }

  Future<Object?> _forwardItem(
    Event item, {
    required GalleryGroupRef? gallery,
    required ForwardUploads uploads,
    required bool announce,
  }) async {
    final txid = room.client.generateUniqueTransactionId();
    final copy = forwardedContent(item, gallery: gallery);
    Object? failure;
    Future<bool> send() async {
      if (_isDiscarded(txid, gallery?.id)) return true;
      return _sendThenDropIfDiscarded(
        txid: txid,
        galleryId: gallery?.id,
        send: () => room.sendEvent(copy, type: item.type, txid: txid),
        onUndelivered: (error) => failure ??= error,
      );
    }

    final delivered = await _guardedSend(
      txid,
      !forwardNeedsUpload(item, room)
          ? send
          : () => _withSendProgress(
              PendingAttachmentSend(
                eventId: txid,
                kind: switch (roomMediaKindOf(item)) {
                  RoomMediaKind.photo => SendMediaKind.photo,
                  RoomMediaKind.video => SendMediaKind.video,
                  RoomMediaKind.file || null => SendMediaKind.file,
                },
                width: item.mediaWidth,
                height: item.mediaHeight,
                compresses: false,
              ),
              (progress) async {
                final plain = await uploads.plainMedia(
                  item,
                  onProgress: progress.upload,
                );
                copy
                  ..remove('file')
                  ..addAll(plain);
                return send();
              },
            ),
      onFailed: (error) {
        failure = error;
        _recordFailed(
          FailedForwardSend(item, gallery: gallery),
          error,
          announce: announce,
        );
      },
      announce: announce,
    );
    if (delivered ?? false) return null;
    return failure ?? const ForwardNotSent();
  }

  Future<void> holdCopies(
    List<String> paths,
    Future<void> Function() body,
  ) async {
    _copies.addAll(paths);
    for (final path in paths) {
      _copyUses.update(path, (uses) => uses + 1, ifAbsent: () => 1);
    }
    try {
      await body();
    } finally {
      for (final path in paths) {
        final uses = _copyUses[path]! - 1;
        if (uses > 0) {
          _copyUses[path] = uses;
        } else {
          _copyUses.remove(path);
        }
      }
      await _releaseCopies(paths);
    }
  }

  Future<void> sendComposed(List<ComposedMedia> composed) =>
      _keepingUploadAlive(
        () => _sendAsGallery(
          composed,
          (media, gallery) => _sendComposedItem(media, gallery: gallery),
        ),
      );

  Future<List<T>> _sendAsGallery<I, T>(
    List<I> items,
    Future<T> Function(I item, GalleryGroupRef? gallery) send,
  ) {
    final groupId = items.length > 1
        ? room.client.generateUniqueTransactionId()
        : null;
    return _discarded.whileSending([groupId], () async {
      final results = <T>[];
      for (final (index, item) in items.indexed) {
        if (_discarded.contains(room, [groupId])) break;
        results.add(
          await send(
            item,
            groupId == null
                ? null
                : GalleryGroupRef(
                    id: groupId,
                    index: index,
                    count: items.length,
                  ),
          ),
        );
      }
      return results;
    });
  }

  Future<void> sendFile(
    Uint8List bytes, {
    required String name,
    String? mimeType,
  }) {
    final txid = room.client.generateUniqueTransactionId();
    return _guardedSend(
      txid,
      () => _withSendProgress(
        PendingAttachmentSend(eventId: txid, kind: SendMediaKind.file),
        (progress) => _sendFileEvent(
          MatrixFile.fromMimeType(bytes: bytes, name: name, mimeType: mimeType),
          txid: txid,
          onUploadProgress: progress.upload,
        ),
      ),
      onFailed: (error) => _sayFailed(error, _l10n.chatNotSentFailed),
    );
  }

  Future<void> sendVoice(
    Uint8List bytes, {
    required Duration duration,
    required List<int> waveform,
  }) async {
    try {
      await _sendFileEvent(
        MatrixFile(
          bytes: bytes,
          name: 'Voice message.ogg',
          mimeType: 'audio/ogg',
        ),
        txid: room.client.generateUniqueTransactionId(),
        extraContent: {
          'org.matrix.msc3245.voice': {},
          'org.matrix.msc1767.audio': {
            'duration': duration.inMilliseconds,
            'waveform': waveform,
          },
        },
      );
    } catch (e, s) {
      reportCaught('send voice message', e, s);
      _sayFailed(e, _l10n.chatVoiceMessageNotSent);
    }
  }

  Future<void> retry(FailedMediaSend failed) async {
    if (!_failed.remove(failed)) return;
    _changed();
    await holdCopies([?failed.path], () async {
      switch (failed) {
        case FailedComposedSend(:final media):
          await _sendComposedItem(media, gallery: failed.gallery);
        case FailedForwardSend(:final event):
          await _forwardItem(
            event,
            gallery: failed.gallery,
            uploads: ForwardUploads(),
            announce: true,
          );
      }
    });
  }

  Future<void> discardUnsent(Event event) async {
    await _discarded.discardUnsent(event);
    final send = _sends[sendIdentity(event).txid];
    if (send == null) return;
    send.stop();
    if (!event.status.isSending) return;
    await runBestEffort(event.cancelSend, label: 'remove a stopped send');
  }

  Future<void> resend(Event event) async {
    final (:txid, :galleryId) = sendIdentity(event);
    if (_isDiscarded(txid, galleryId)) {
      await runBestEffort(
        () => _discarded.discardUnsent(event),
        label: 'discard a deleted send',
      );
      return;
    }
    await runBestEffort(
      () => _sendThenDropIfDiscarded(
        txid: txid,
        galleryId: galleryId,
        send: () => resendUnsent(event),
      ),
      label: 'sendAgain',
    );
  }

  void retryAll(Timeline? timeline) {
    for (final failed in [..._failed]) {
      unawaited(retry(failed));
    }
    if (timeline == null) return;
    for (final event in notSentOwnEvents(timeline)) {
      unawaited(resend(event));
    }
  }

  Future<void> dropGalleries(Iterable<Event> events) async {
    final ids = {for (final event in events) ?sendIdentity(event).galleryId};
    for (final id in ids) {
      await _discarded.add(room, id);
    }
    final dropped = [
      for (final failed in _failed)
        if (ids.contains(failed.gallery?.id)) failed,
    ];
    if (dropped.isEmpty) return;
    _failed.removeWhere(dropped.contains);
    _changed();
    unawaited(_releaseCopies([for (final failed in dropped) ?failed.path]));
  }

  Future<void> _sendComposedItem(
    ComposedMedia media, {
    required GalleryGroupRef? gallery,
  }) {
    final txid = room.client.generateUniqueTransactionId();
    return _guardedSend(
      txid,
      () => switch (media) {
        ComposedImage() => _sendPhoto(media, txid: txid, gallery: gallery),
        ComposedVideo() => _sendVideo(media, txid: txid, gallery: gallery),
      },
      onFailed: (error) =>
          _recordFailed(FailedComposedSend(media, gallery: gallery), error),
    );
  }

  Future<void> _sendPhoto(
    ComposedImage image, {
    required String txid,
    required GalleryGroupRef? gallery,
  }) async {
    final bytes = await fileSystem.file(image.path).readAsBytes();
    await _withSendProgress(
      PendingAttachmentSend(
        eventId: txid,
        previewBytes: bytes,
        kind: SendMediaKind.photo,
      ),
      (progress) async {
        final prepared = await prepareImageForSend(
          bytes,
          reduceMediaSize: _reduceMediaSize(),
          onProgress: progress.compression,
        );
        await _sendFileEvent(
          prepared.file,
          txid: txid,
          thumbnail: prepared.thumbnail,
          extraContent: _attachmentExtraContent(
            caption: image.caption,
            gallery: gallery,
          ),
          galleryId: gallery?.id,
          onUploadProgress: progress.upload,
        );
      },
    );
  }

  Future<void> _sendVideo(
    ComposedVideo video, {
    required String txid,
    required GalleryGroupRef? gallery,
  }) => _withSendProgress(
    PendingAttachmentSend(
      eventId: txid,
      width: video.width,
      height: video.height,
      kind: SendMediaKind.video,
    ),
    (progress) async {
      final prepared = await prepareVideoForSend(
        video.path,
        reduceMediaSize: _reduceMediaSize(),
        fallbackWidth: video.width,
        fallbackHeight: video.height,
        fallbackDurationMs: video.durationMs,
        onThumbnail: (thumbnail) => progress.preview(
          thumbnail.bytes,
          width: thumbnail.width,
          height: thumbnail.height,
        ),
        onProgress: progress.compression,
      );
      await _sendFileEvent(
        prepared.file,
        txid: txid,
        thumbnail: prepared.thumbnail,
        extraContent: _attachmentExtraContent(
          caption: video.caption,
          gallery: gallery,
        ),
        galleryId: gallery?.id,
        onUploadProgress: progress.upload,
      );
    },
  );

  Future<T?> _guardedSend<T>(
    String txid,
    Future<T> Function() send, {
    required void Function(Object error) onFailed,
    bool announce = true,
  }) async {
    try {
      return await send();
    } on MediaProcessingException catch (e) {
      if (announce) _say(e.message);
    } on FileTooBigMatrixException catch (e) {
      await discardSendPlaceholder(room, txid);
      if (announce) _say(tooLargeToSendMessage(_l10n, e));
    } catch (e, s) {
      reportCaught('send attachment', e, s);
      await discardSendPlaceholder(room, txid);
      onFailed(e);
    }
    return null;
  }

  Future<T> _withSendProgress<T>(
    PendingAttachmentSend pending,
    Future<T> Function(_SendProgressSink progress) send,
  ) {
    return _keepingUploadAlive(() async {
      var current = pending;
      void publish(PendingAttachmentSend next) {
        current = next;
        if (!_disposed) _pending.value = next;
        unawaited(
          UploadForegroundService.instance.updateProgress(
            label: next.progressLabel(_l10n),
            fraction: next.progress,
          ),
        );
      }

      void advance(SendStage stage, double? fraction) =>
          publish(current.withStage(stage, fraction));

      publish(pending);
      try {
        return await send(
          _SendProgressSink(
            compression: (fraction) => advance(SendStage.compressing, fraction),
            upload: (fraction) => advance(SendStage.uploading, fraction),
            preview: (bytes, {width, height}) => publish(
              current.withPreview(bytes, width: width, height: height),
            ),
          ),
        );
      } finally {
        if (!_disposed) _pending.value = null;
      }
    });
  }

  Future<T> _keepingUploadAlive<T>(Future<T> Function() body) async {
    final service = UploadForegroundService.instance;
    await service.acquire();
    try {
      return await body();
    } finally {
      await service.release();
    }
  }

  bool _isDiscarded(String txid, String? galleryId) =>
      _discarded.contains(room, [txid, galleryId]);

  Future<void> _sendFileEvent(
    MatrixFile file, {
    required String txid,
    MatrixImageFile? thumbnail,
    Map<String, dynamic>? extraContent,
    String? galleryId,
    void Function(double fraction)? onUploadProgress,
  }) async {
    if (_isDiscarded(txid, galleryId)) return;
    await _sendThenDropIfDiscarded(
      txid: txid,
      galleryId: galleryId,
      onUploadProgress: onUploadProgress,
      send: () => room.sendFileEvent(
        file,
        txid: txid,
        thumbnail: thumbnail,
        extraContent: extraContent,
      ),
    );
  }

  Future<bool> _sendThenDropIfDiscarded({
    required String txid,
    required String? galleryId,
    required Future<String?> Function() send,
    void Function(double fraction)? onUploadProgress,
    void Function(Object error)? onUndelivered,
  }) async {
    final scope = _sends[txid] = SendScope(onProgress: onUploadProgress);
    final sending = _discarded.whileSending([
      txid,
      galleryId,
    ], () => _sendUnlessDiscarded(txid, galleryId, () => scope.run(send)));
    final bool delivered;
    try {
      delivered = await Future.any([sending, scope.stopped.then((_) => true)]);
    } finally {
      _sends.remove(txid);
    }
    if (scope.isStopped) _keepRemoved(txid, until: sending);
    if (!delivered) {
      if (scope.failure case final error?) onUndelivered?.call(error);
    }
    return delivered;
  }

  void _keepRemoved(String txid, {required Future<void> until}) {
    final shownAgain = room.client.onTimelineEvent.stream
        .where(
          (event) =>
              event.room.id == room.id &&
              !event.status.isSent &&
              event.matchesEventOrTransactionId(txid),
        )
        .listen(
          (event) => unawaited(
            runBestEffort(
              event.cancelSend,
              label: 'remove a stopped send shown again',
            ),
          ),
        );
    until.whenComplete(shownAgain.cancel).ignore();
  }

  Future<bool> _sendUnlessDiscarded(
    String txid,
    String? galleryId,
    Future<String?> Function() send,
  ) async {
    String? eventId;
    try {
      eventId = await send();
    } catch (_) {
      if (!_isDiscarded(txid, galleryId)) rethrow;
    }
    if (!_isDiscarded(txid, galleryId)) return eventId != null;
    try {
      if (eventId == null) {
        await discardSendPlaceholder(room, txid);
      } else {
        await room.redactEvent(eventId);
      }
    } catch (e, s) {
      reportCaught('delete a message that landed after its delete', e, s);
      _sayFailed(
        e,
        galleryId == null
            ? _l10n.chatDeleteOneFailed
            : _l10n.chatDeleteManyFailed,
      );
    } finally {
      await _discarded.remove(room, txid);
    }
    return true;
  }

  Map<String, dynamic>? _attachmentExtraContent({
    required String? caption,
    required GalleryGroupRef? gallery,
  }) {
    final content = <String, dynamic>{
      if (caption != null && caption.isNotEmpty) 'body': caption,
      ...?gallery?.content,
    };
    return content.isEmpty ? null : content;
  }

  void _recordFailed(
    FailedMediaSend failed,
    Object error, {
    bool announce = true,
  }) {
    if (_discarded.contains(room, [failed.gallery?.id])) return;
    if (_disposed) {
      if (announce) _sayFailed(error, _l10n.chatNotSentFailed);
      return;
    }
    _failed.add(failed);
    _changed();
    if (announce && !_chatOpen()) {
      _sayFailed(error, _l10n.chatNotSentFailed);
    }
  }

  Future<void> _releaseCopies(List<String> paths) async {
    final unused = [
      for (final path in paths)
        if (_copies.contains(path) &&
            !_copyUses.containsKey(path) &&
            !_awaitsRetry(path))
          path,
    ];
    _copies.removeAll(unused);
    await Future.wait(unused.map(discardTemporaryCopy));
  }

  bool _awaitsRetry(String path) =>
      !_disposed && _failed.any((failed) => failed.path == path);

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_releaseCopies([..._copies]));
    _pending.dispose();
    super.dispose();
  }
}

class _SendProgressSink {
  final void Function(double fraction) compression;
  final void Function(double fraction) upload;
  final void Function(Uint8List bytes, {int? width, int? height}) preview;

  const _SendProgressSink({
    required this.compression,
    required this.upload,
    required this.preview,
  });
}
