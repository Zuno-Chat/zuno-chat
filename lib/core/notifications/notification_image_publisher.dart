import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

import '../platform/platform_capabilities.dart';
import 'message_notification_image.dart';

typedef ImagePublisher = Future<String?> Function(NotificationImage image);

const _channel = MethodChannel('zuno/conversations');

Future<String?> publishNotificationImage(
  NotificationImage image, {
  PlatformCapabilities? capabilities,
}) async {
  final supported = (capabilities ?? ambientCapabilities).notificationImages;
  if (!supported) return null;
  try {
    return await _channel.invokeMethod<String>('publishNotificationImage', {
      'bytes': image.bytes,
      'mimeType': image.mimeType,
    });
  } catch (e) {
    debugPrint('zuno/notifications: could not publish thumbnail ($e)');
    return null;
  }
}
