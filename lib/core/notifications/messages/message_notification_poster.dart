import 'dart:typed_data';

import 'package:matrix/matrix.dart';

import '../../errors/best_effort.dart';
import '../../matrix/attachment_cache.dart';
import '../../matrix/mxc_avatar_image.dart' show AvatarBucket, avatarCacheKey;
import '../../platform/platform_capabilities.dart';
import '../../push/handling/push_timing.dart';
import '../notification_avatar.dart';
import '../settings/notification_preview.dart';
import 'message_notification_content.dart';
import 'message_notification_image.dart';
import 'message_notifications.dart';
import 'notification_avatar_cache.dart';
import 'notification_image_publisher.dart';

const notificationAvatarTimeout = Duration(seconds: 5);

typedef AvatarFetcher = Future<Uint8List?> Function(Client client, Uri url);

// shortcut: iOS posts carry no avatars or images (notificationAvatars and notificationImages are off), add avatars once communication notifications and donations ship, and re-scope images to in-front posts or retire the flag
Future<void> postMessageNotification(
  MessageNotificationContent content, {
  required Client client,
  required NotificationPreview preview,
  bool placeholder = false,
  bool isMessage = true,
  AvatarFetcher? fetchAvatar,
  DiskAttachmentCache? appAvatars,
  Future<NotificationImage?> Function()? fetchImage,
  ImagePublisher publishImage = publishNotificationImage,
  void Function()? onPosted,
  void Function(Future<void> refinement)? onRefining,
  PushTiming? timing,
  PlatformCapabilities? capabilities,
}) async {
  final platform = capabilities ?? ambientCapabilities;
  final avatarUrl = platform.notificationAvatars
      ? content.senderAvatarUrl
      : null;
  final kept =
      avatarUrl != null &&
      await NotificationAvatarCache.instance.contains(avatarUrl);
  final fromApp = avatarUrl == null || kept
      ? null
      : await _avatarTheAppShows(avatarUrl, appAvatars);

  Future<void> show({
    Uint8List? avatar,
    bool refine = false,
    String? imageUri,
    String? imageMimeType,
  }) => MessageNotifications.instance.showMessage(
    content,
    preview: preview,
    isMessage: isMessage,
    senderAvatar: avatar,
    placeholder: placeholder,
    refine: refine,
    imageUri: imageUri,
    imageMimeType: imageMimeType,
    timing: refine ? null : timing,
  );

  await show(avatar: fromApp);
  onPosted?.call();
  if (placeholder) return;

  final needsAvatar =
      avatarUrl != null &&
      !kept &&
      fromApp == null &&
      preview != NotificationPreview.nothing;
  final needsImage =
      content.isPhoto &&
      fetchImage != null &&
      platform.notificationImages &&
      preview == NotificationPreview.full;
  if (!needsAvatar && !needsImage) return;

  Future<void> refine() async {
    if (needsAvatar) {
      final fetch =
          fetchAvatar ??
          (client, url) => fetchNotificationAvatarBytes(
            client,
            url,
            timeout: notificationAvatarTimeout,
          );
      final bytes = await fetch(client, avatarUrl);
      if (bytes != null) await show(avatar: bytes, refine: true);
    }

    if (!needsImage) return;
    final image = await fetchImage();
    if (image == null) return;
    final uri = await publishImage(image);
    if (uri == null) return;
    await show(refine: true, imageUri: uri, imageMimeType: image.mimeType);
  }

  if (onRefining == null) {
    await refine();
    return;
  }
  onRefining(runBestEffort(refine, label: 'notification refinement'));
}

Future<Uint8List?> _avatarTheAppShows(
  Uri avatarUrl,
  DiskAttachmentCache? appAvatars,
) => (appAvatars ?? DiskAttachmentCache.instance).get(
  avatarCacheKey(avatarUrl, AvatarBucket.small),
  expires: false,
);
