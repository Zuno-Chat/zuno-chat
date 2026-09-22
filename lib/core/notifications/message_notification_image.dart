import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:matrix/matrix.dart';

const messageNotificationImageTimeout = Duration(seconds: 8);

class NotificationImage {
  final Uint8List bytes;
  final String mimeType;

  const NotificationImage({required this.bytes, required this.mimeType});
}

Future<NotificationImage?> fetchMessageNotificationImage(
  Event event, {
  Future<MatrixFile> Function()? download,
  Duration timeout = messageNotificationImageTimeout,
}) async {
  final fetch =
      download ?? () => event.downloadAndDecryptAttachment(getThumbnail: true);
  try {
    final file = await fetch().timeout(timeout);
    return NotificationImage(bytes: file.bytes, mimeType: file.mimeType);
  } catch (e) {
    debugPrint('zuno/notifications: could not fetch thumbnail image: $e');
    return null;
  }
}
