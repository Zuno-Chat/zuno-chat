import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:gal/gal.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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

String? _mimeTypeOf(Event event) {
  final mimeType = event.attachmentMimetype;
  return mimeType.isEmpty ? null : mimeType;
}

Future<Uint8List> _download(Event event) async =>
    (await event.downloadAndDecryptAttachment()).bytes;

Future<Uint8List> _cachedAttachmentBytes(Event event) => fetchCachedAttachment(
  attachmentCacheKey(event, thumbnail: false),
  () => _download(event),
);

Future<File> _cachedAttachmentFile(Event event) => fetchCachedAttachmentFile(
  attachmentCacheKey(event, thumbnail: false),
  () => _download(event),
);

Future<String> _tempCopy(Event event) async {
  final source = await _cachedAttachmentFile(event);
  final dir = await getTemporaryDirectory();
  final path = p.join(dir.path, attachmentFileName(event));
  await source.copy(path);
  return path;
}

Future<String?> saveAttachment(Event event) async {
  switch (attachmentSaveTarget(event)) {
    case AttachmentSaveTarget.photos:
      await Gal.putImageBytes(
        await _cachedAttachmentBytes(event),
        name: p.basenameWithoutExtension(attachmentFileName(event)),
      );
      return 'Saved to Photos';
    case AttachmentSaveTarget.videos:
      final path = await _tempCopy(event);
      try {
        await Gal.putVideo(path);
      } finally {
        unawaited(File(path).delete().catchError((_) => File(path)));
      }
      return 'Saved to Videos';
    case AttachmentSaveTarget.file:
      final bytes = await (await _cachedAttachmentFile(event)).readAsBytes();
      final uri = await FilePicker.saveFile(
        fileName: attachmentFileName(event),
        bytes: bytes,
        mimeType: _mimeTypeOf(event) ?? 'application/octet-stream',
      );
      return uri == null ? null : 'Saved';
  }
}

Future<int> saveAttachments(List<Event> events) async {
  var saved = 0;
  for (final event in events) {
    try {
      if (await saveAttachment(event) != null) saved++;
    } catch (_) {}
  }
  return saved;
}

String savedSummary({required int saved, required int total}) {
  if (saved == 0) return 'Could not save';
  if (saved < total) return 'Saved $saved of $total';
  return saved == 1 ? 'Saved 1 item' : 'Saved $saved items';
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
}) async {
  if (events.isEmpty) return;
  if (onPreparing != null && !await _allCached(events)) onPreparing();
  final files = [
    for (final event in events)
      XFile(await _tempCopy(event), mimeType: _mimeTypeOf(event)),
  ];
  await SharePlus.instance.share(ShareParams(files: files));
}
