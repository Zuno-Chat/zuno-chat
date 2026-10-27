import 'package:matrix/matrix.dart';

import '../../../core/errors/caught_errors.dart';
import '../../../core/files/file_system.dart';
import '../../../core/matrix/attachment_actions.dart';
import '../../../core/matrix/upload_http_client.dart';

class ForwardUploads {
  final _uploads = <String, _PlainUpload>{};

  Future<Map<String, Object?>> plainMedia(
    Event item, {
    void Function(double fraction)? onProgress,
  }) {
    final upload = _uploads.putIfAbsent(item.eventId, () => _PlainUpload(item));
    if (onProgress != null) upload.listeners.add(onProgress);
    return upload.media;
  }
}

class _PlainUpload {
  _PlainUpload(Event item) {
    media = _upload(item);
  }

  final listeners = <void Function(double fraction)>[];
  late final Future<Map<String, Object?>> media;

  Future<Map<String, Object?>> _upload(Event item) async {
    final url = item.isAttachmentEncrypted ? await _uploadFile(item) : null;
    final info = Map<String, Object?>.of(item.infoMap);
    if (item.isThumbnailEncrypted) {
      info.remove('thumbnail_file');
      final thumbnailUrl = await _uploadThumbnail(item);
      if (thumbnailUrl == null) {
        info.remove('thumbnail_info');
      } else {
        info['thumbnail_url'] = thumbnailUrl.toString();
      }
    }
    return {'url': ?url?.toString(), 'info': info};
  }

  Future<Uri> _uploadFile(Event item) async {
    final cached = await cachedAttachmentFile(item);
    final bytes = await fileSystem.file(cached.path).readAsBytes();
    return SendScope(onProgress: _progress).run(
      () => item.room.client.uploadContent(
        bytes,
        filename: attachmentFileName(item),
        contentType: attachmentMimeType(item),
      ),
    );
  }

  Future<Uri?> _uploadThumbnail(Event item) async {
    final mimeType = item.thumbnailMimetype;
    try {
      final bytes = await cachedAttachmentBytes(item, thumbnail: true);
      return await SendScope().run(
        () => item.room.client.uploadContent(
          bytes,
          contentType: mimeType.isEmpty ? null : mimeType,
        ),
      );
    } catch (e, s) {
      reportCaught('forward a thumbnail', e, s);
      return null;
    }
  }

  void _progress(double fraction) {
    for (final listener in listeners) {
      listener(fraction);
    }
  }
}
