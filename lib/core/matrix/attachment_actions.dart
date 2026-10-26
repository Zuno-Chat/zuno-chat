import 'dart:async';
import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:matrix/matrix.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart' show XFile;

import '../errors/best_effort.dart';
import '../errors/caught_errors.dart';
import '../files/file_export.dart';
import '../files/file_system.dart';
import '../l10n/l10n.dart';
import '../platform/platform_capabilities.dart';
import '../share/outbound_share.dart';
import 'attachment_cache.dart';

const _maxFileNameLength = 64;

String safeAttachmentFileName(String rawName, {String fallback = 'file'}) {
  final base = p.basename(rawName.replaceAll(r'\', '/'));
  final cleaned = base.replaceAll(RegExp(r'[\x00-\x1f\x7f/\\]'), '').trim();
  if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') return fallback;
  if (cleaned.length <= _maxFileNameLength) return cleaned;
  final extension = p.extension(cleaned);
  final stemBudget = _maxFileNameLength - extension.length;
  if (stemBudget <= 0) return cleaned.substring(0, _maxFileNameLength);
  return cleaned.substring(0, stemBudget) + extension;
}

enum AttachmentSaveTarget { photos, videos, file }

AttachmentSaveTarget attachmentSaveTarget(Event event) {
  if (event.messageType == MessageTypes.Image ||
      event.messageType == MessageTypes.Sticker) {
    return AttachmentSaveTarget.photos;
  }
  if (event.messageType == MessageTypes.Video) {
    return AttachmentSaveTarget.videos;
  }
  return AttachmentSaveTarget.file;
}

String attachmentFileName(Event event) => safeAttachmentFileName(
  event.content.tryGet<String>('filename') ?? event.body,
);

String? attachmentMimeType(Event event) {
  final mimeType = event.attachmentMimetype;
  return mimeType.isEmpty ? null : mimeType;
}

String _handedOverName(Event event) {
  final name = attachmentFileName(event);
  if (lookupMimeType(name) != null) return name;
  final mimeType = attachmentMimeType(event);
  if (mimeType == null || mimeType == 'application/octet-stream') return name;
  final extension = extensionFromMime(mimeType);
  return extension == null ? name : safeAttachmentFileName('$name.$extension');
}

Future<Uint8List> _download(Event event) async =>
    (await event.downloadAndDecryptAttachment()).bytes;

Future<Uint8List> _cachedAttachmentBytes(Event event) => fetchCachedAttachment(
  attachmentCacheKey(event, thumbnail: false),
  () => _download(event),
);

Future<String> _handOver(Event event) async => (await fetchAttachmentHandover(
  attachmentCacheKey(event, thumbnail: false),
  _handedOverName(event),
  () => _download(event),
)).path;

Future<T> _fromHandedOverCopy<T>(
  Event event,
  Future<T> Function(String path) use,
) async {
  final path = await _handOver(event);
  try {
    return await use(path);
  } finally {
    unawaited(
      runBestEffort(
        () => fileSystem.directory(p.dirname(path)).delete(recursive: true),
        label: 'delete a saved copy',
      ),
    );
  }
}

Future<bool> saveAttachment(Event event) async {
  switch (attachmentSaveTarget(event)) {
    case AttachmentSaveTarget.photos:
      await Gal.putImageBytes(
        await _cachedAttachmentBytes(event),
        name: p.basenameWithoutExtension(attachmentFileName(event)),
      );
      return true;
    case AttachmentSaveTarget.videos:
      await _fromHandedOverCopy(event, Gal.putVideo);
      return true;
    case AttachmentSaveTarget.file:
      return _fromHandedOverCopy(
        event,
        (path) => exportFileAt(
          path,
          mimeType: attachmentMimeType(event) ?? 'application/octet-stream',
        ),
      );
  }
}

bool isGalleryAccessDenied(Object error) =>
    error is GalException && error.type == GalExceptionType.accessDenied;

Future<int> saveAttachments(List<Event> events) async {
  var saved = 0;
  for (final event in events) {
    try {
      if (await saveAttachment(event)) saved++;
    } catch (e, s) {
      if (!isGalleryAccessDenied(e)) reportCaught('save attachment', e, s);
    }
  }
  return saved;
}

String savedMessage(AppLocalizations l10n, Event event) =>
    switch (attachmentSaveTarget(event)) {
      AttachmentSaveTarget.photos => l10n.matrixSavedToPhotos,
      AttachmentSaveTarget.videos => l10n.matrixSavedToVideos,
      AttachmentSaveTarget.file => l10n.matrixSaved,
    };

String savedSummary(
  AppLocalizations l10n, {
  required int saved,
  required int total,
}) {
  if (saved == 0) return l10n.matrixSaveNone;
  if (saved < total) return l10n.matrixSavedSome(saved, total);
  return l10n.matrixSavedItems(saved);
}

Future<bool> _allCached(List<Event> events) async {
  for (final event in events) {
    final key = attachmentCacheKey(event, thumbnail: false);
    if (!await isAttachmentCached(key)) return false;
  }
  return true;
}

Future<void> shareAttachments(
  List<Event> events, {
  void Function()? onPreparing,
  PlatformCapabilities? capabilities,
}) async {
  if (events.isEmpty) return;
  if (onPreparing != null && !await _allCached(events)) onPreparing();
  final files = [
    for (final event in events)
      XFile(await _handOver(event), mimeType: attachmentMimeType(event)),
  ];
  await shareFiles(files, capabilities: capabilities);
}
