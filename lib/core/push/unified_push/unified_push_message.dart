import 'dart:convert';
import 'dart:typed_data';

import 'package:matrix/matrix.dart';

PushNotification? pushNotificationFromMessageBytes(Uint8List bytes) {
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) return null;
  final notification = decoded['notification'];
  return PushNotification.fromJson(
    notification is Map<String, Object?> ? notification : decoded,
  );
}
