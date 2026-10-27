import 'package:matrix/matrix.dart';

import '../../../core/matrix/forwarded_message.dart';
import '../../../core/matrix/media_gallery_group.dart';
import '../../../core/matrix/reply_fallback.dart';
import '../../../core/matrix/room_encryption.dart';
import '../../../core/matrix/room_media_feed.dart';

bool canForward(Event event) => roomMediaKindOf(event) != null;

bool forwardNeedsUpload(Event event, Room target) =>
    !sendsEncrypted(target) &&
    (event.isAttachmentEncrypted || event.isThumbnailEncrypted);

Map<String, Object?> forwardedContent(Event event, {GalleryGroupRef? gallery}) {
  final content = Map<String, Object?>.of(event.content)
    ..remove('m.relates_to')
    ..remove('m.new_content')
    ..remove(galleryGroupKey)
    ..remove('format')
    ..remove('formatted_body')
    ..['m.mentions'] = <String, Object?>{}
    ..[forwardedKey] = true
    ..addAll(gallery?.content ?? const {});
  final body = content['body'];
  if (body is String) content['body'] = stripReplyFallback(body);
  return content;
}
