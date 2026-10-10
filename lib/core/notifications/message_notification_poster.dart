import 'dart:typed_data';

import 'package:matrix/matrix.dart';

import '../calls/notifications/call_notification_service.dart';
import '../calls/notifications/caller_avatar.dart';
import '../errors/best_effort.dart';
import '../matrix/attachment_cache.dart';
import '../matrix/mxc_avatar_image.dart' show AvatarBucket, avatarCacheKey;
import '../platform/platform_capabilities.dart';
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

  await show(avatar: fromApp);
  onPosted?.call();
  if (placeholder) return;

  final needsAvatar = avatarUrl != null && !kept && fromApp == null;
  final needsImage =
      content.isPhoto && fetchImage != null && platform.notificationImages;
  if (!needsAvatar && !needsImage) return;

  Future<void> refine() async {
    if (needsAvatar) {
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
