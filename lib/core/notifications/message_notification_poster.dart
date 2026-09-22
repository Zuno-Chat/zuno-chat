import 'dart:typed_data';

import 'package:matrix/matrix.dart';

import '../calls/notifications/call_notification_service.dart';
import '../calls/notifications/caller_avatar.dart';
import '../push/push_timing.dart';
import 'message_notification_content.dart';
import 'message_notification_image.dart';
import 'notification_avatar_cache.dart';
import 'notification_image_publisher.dart';

const notificationAvatarTimeout = Duration(seconds: 5);

typedef AvatarFetcher = Future<Uint8List?> Function(Client client, Uri url);

Future<void> postMessageNotification(
  MessageNotificationContent content, {
  required Client client,
  bool placeholder = false,
  bool includeMessageActions = true,
  AvatarFetcher? fetchAvatar,
  Future<NotificationImage?> Function()? fetchImage,
  ImagePublisher publishImage = publishNotificationImage,
  void Function()? onPosted,
  PushTiming? timing,
}) async {
  final avatarUrl = content.senderAvatarUrl;
  final cached = avatarUrl == null
      ? null
      : await NotificationAvatarCache.instance.read(avatarUrl);

  Future<void> show({
    Uint8List? avatar,
    bool refine = false,
    String? imageUri,
    String? imageMimeType,
  }) => CallNotificationService.instance.showMessage(
    content,
    includeMessageActions: includeMessageActions,
    senderAvatar: avatar,
    placeholder: placeholder,
    refine: refine,
    imageUri: imageUri,
    imageMimeType: imageMimeType,
    timing: refine ? null : timing,
  );

  await show(avatar: cached);
  onPosted?.call();
  if (placeholder) return;

  if (avatarUrl != null && cached == null) {
    final fetch =
        fetchAvatar ??
        (client, url) => fetchCallerAvatarBytes(
          client,
          url,
          timeout: notificationAvatarTimeout,
        );
    final bytes = await fetch(client, avatarUrl);
    if (bytes != null) await show(avatar: bytes, refine: true);
  }

  if (!content.isPhoto || fetchImage == null) return;
  final image = await fetchImage();
  if (image == null) return;
  final uri = await publishImage(image);
  if (uri == null) return;
  await show(refine: true, imageUri: uri, imageMimeType: image.mimeType);
}
