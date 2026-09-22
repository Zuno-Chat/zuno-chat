import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

import 'message_notification_image.dart';

typedef ImagePublisher = Future<String?> Function(NotificationImage image);

const _channel = MethodChannel('zuno/conversations');

Future<String?> publishNotificationImage(NotificationImage image) async {
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
