import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/best_effort.dart';
import '../../../core/errors/caught_errors.dart';
import '../../../core/errors/global_error_handler.dart';
import '../../../core/files/picked_file.dart';
import '../../../core/l10n/display_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/currently_open_room_provider.dart';
import '../../../core/matrix/image_send_preparation.dart';
import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/matrix/media_gallery_group.dart';
import '../../../core/matrix/media_processing_exception.dart';
import '../../../core/matrix/send_failure.dart';
import '../../../core/matrix/send_progress.dart';
import '../../../core/matrix/upload_foreground_service.dart';
import '../../../core/matrix/video_send_preparation.dart';
import '../../../core/settings/app_preferences_provider.dart';
import 'composed_image.dart';
import 'composed_media.dart';
import 'composed_video.dart';
import 'discarded_sends.dart';
import 'pending_attachment_send.dart';
import 'unsent_events.dart';

final roomSenderProvider = Provider.family<RoomSender, Room>((ref, room) {
  final container = ref.container;
  final sender = RoomSender(
    room: room,
    discarded: ref.watch(discardedSendsProvider),
    uploadProgress: () =>
        container.read(uploadProgressHttpClientProvider).onUploadProgress,
    reduceMediaSize: () => container.read(reduceMediaSizeProvider),
    chatOpen: () => container.read(currentlyOpenRoomIdProvider) == room.id,
    say: _snack,
  );
  ref.onDispose(sender.dispose);
  return sender;
});

void _snack(@displayText String message) => globalScaffoldMessengerKey
    .currentState
    ?.showSnackBar(SnackBar(content: Text(message)));

class RoomSender extends ChangeNotifier {
  RoomSender({
    required this.room,
    required this._discarded,
    required this._uploadProgress,
    required this._reduceMediaSize,
    required this._chatOpen,
    required this._say,
  });

  final Room room;
  final DiscardedSends _discarded;
  final Stream<double> Function() _uploadProgress;
  final bool Function() _reduceMediaSize;
  final bool Function() _chatOpen;
  final void Function(String message) _say;

  final _pending = ValueNotifier<PendingAttachmentSend?>(null);
  final List<FailedMediaSend> _failed = [];
  final _copies = <String>{};
  final _copyUses = <String, int>{};
  bool _disposed = false;

  ValueListenable<PendingAttachmentSend?> get pending => _pending;

  late final List<FailedMediaSend> failed = UnmodifiableListView(_failed);

  AppLocalizations get _l10n => deviceLocalizations();

  Future<void> sendText(
    String text, {
    Event? editing,
    Event? replyingTo,
  }) async {
    await runBestEffort(
      () => room.sendTextEvent(
        text,
        editEventId: editing?.eventId,
        inReplyTo: replyingTo,
        parseMarkdown: false,
        parseCommands: false,
      ),
      label: 'send a text message',
    );
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

  Future<void> sendComposed(List<ComposedMedia> composed) {
    final groupId = composed.length > 1
        ? room.client.generateUniqueTransactionId()
        : null;
    return _keepingUploadAlive(
      () => _discarded.whileSending([groupId], () async {
        for (final (i, media) in composed.indexed) {
          if (_discarded.contains(room, [groupId])) break;
          final gallery = groupId == null
              ? null
              : GalleryGroupRef(id: groupId, index: i, count: composed.length);
          await switch (media) {
            ComposedImageResult(:final image) => _sendPhoto(
              image,
              gallery: gallery,
            ),
            ComposedVideoResult(:final video) => _sendVideo(
              video,
              gallery: gallery,
            ),
          };
        }
      }),
    );
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
        (_) => _sendFileEvent(
          MatrixFile.fromMimeType(bytes: bytes, name: name, mimeType: mimeType),
          txid: txid,
        ),
      ),
      onFailed: () => _say(_l10n.chatNotSentTryAgain),
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
      _say(_l10n.chatVoiceMessageNotSent);
    }
  }

  Future<void> retry(FailedMediaSend failed) async {
    if (!_failed.remove(failed)) return;
    _changed();
    await holdCopies([?failed.path], () async {
      switch (failed) {
        case FailedMediaSend(photo: final photo?):
          await _sendPhoto(photo, gallery: failed.gallery);
        case FailedMediaSend(video: final video?):
          await _sendVideo(video, gallery: failed.gallery);
      }
    });
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

  Future<void> _sendPhoto(ComposedImage image, {GalleryGroupRef? gallery}) {
    final txid = room.client.generateUniqueTransactionId();
    return _guardedSend(
      txid,
      () async {
        final bytes = await File(image.path).readAsBytes();
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
            );
          },
        );
      },
      onFailed: () =>
          _recordFailed(FailedMediaSend(gallery: gallery, photo: image)),
    );
  }

  Future<void> _sendVideo(ComposedVideo composed, {GalleryGroupRef? gallery}) {
    final txid = room.client.generateUniqueTransactionId();
    return _guardedSend(
      txid,
      () => _withSendProgress(
        PendingAttachmentSend(
          eventId: txid,
          width: composed.width,
          height: composed.height,
          kind: SendMediaKind.video,
        ),
        (progress) async {
          final prepared = await prepareVideoForSend(
            composed.path,
            reduceMediaSize: _reduceMediaSize(),
            fallbackWidth: composed.width,
            fallbackHeight: composed.height,
            fallbackDurationMs: composed.durationMs,
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
              caption: composed.caption,
              gallery: gallery,
            ),
            galleryId: gallery?.id,
          );
        },
      ),
      onFailed: () =>
          _recordFailed(FailedMediaSend(gallery: gallery, video: composed)),
    );
  }

  Future<void> _guardedSend(
    String txid,
    Future<void> Function() send, {
    required VoidCallback onFailed,
  }) async {
    try {
      await send();
    } on MediaProcessingException catch (e) {
      _say(e.message);
    } on FileTooBigMatrixException catch (e) {
      await discardSendPlaceholder(room, txid);
      _say(tooLargeToSendMessage(_l10n, e));
    } catch (e, s) {
      reportCaught('send attachment', e, s);
      await discardSendPlaceholder(room, txid);
      onFailed();
    }
  }

  Future<void> _withSendProgress(
    PendingAttachmentSend pending,
    Future<void> Function(_SendProgressSink progress) send,
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
      final sub = _uploadProgress().listen(
        (fraction) => advance(SendStage.uploading, fraction),
      );
      try {
        await send(
          _SendProgressSink(
            compression: (fraction) => advance(SendStage.compressing, fraction),
            preview: (bytes, {width, height}) => publish(
              current.withPreview(bytes, width: width, height: height),
            ),
          ),
        );
      } finally {
        await sub.cancel();
        if (!_disposed) _pending.value = null;
      }
    });
  }

  Future<void> _keepingUploadAlive(Future<void> Function() body) async {
    final service = UploadForegroundService.instance;
    await service.acquire();
    try {
      await body();
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
  }) async {
    if (_isDiscarded(txid, galleryId)) return;
    await _sendThenDropIfDiscarded(
      txid: txid,
      galleryId: galleryId,
      send: () => room.sendFileEvent(
        file,
        txid: txid,
        thumbnail: thumbnail,
        extraContent: extraContent,
      ),
    );
  }

  Future<void> _sendThenDropIfDiscarded({
    required String txid,
    required String? galleryId,
    required Future<String?> Function() send,
  }) => _discarded.whileSending([txid, galleryId], () async {
    final eventId = await send();
    if (!_isDiscarded(txid, galleryId)) return;
    try {
      if (eventId == null) {
        await discardSendPlaceholder(room, txid);
      } else {
        await room.redactEvent(eventId);
      }
    } catch (e, s) {
      reportCaught('delete a message that landed after its delete', e, s);
      _say(
        galleryId == null
            ? _l10n.chatDeleteOneFailed
            : _l10n.chatDeleteManyFailed,
      );
    } finally {
      await _discarded.remove(room, txid);
    }
  });

  Map<String, dynamic>? _attachmentExtraContent({
    required String? caption,
    required GalleryGroupRef? gallery,
  }) {
    final content = <String, dynamic>{
      if (caption != null && caption.isNotEmpty) 'body': caption,
      if (gallery != null)
        ...galleryGroupContent(
          id: gallery.id,
          index: gallery.index,
          count: gallery.count,
        ),
    };
    return content.isEmpty ? null : content;
  }

  void _recordFailed(FailedMediaSend failed) {
    if (_discarded.contains(room, [failed.gallery?.id])) return;
    if (_disposed) {
      _say(_l10n.chatNotSentTryAgain);
      return;
    }
    _failed.add(failed);
    _changed();
    if (!_chatOpen()) _say(_l10n.chatNotSentTryAgain);
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
  final void Function(Uint8List bytes, {int? width, int? height}) preview;

  const _SendProgressSink({required this.compression, required this.preview});
}
