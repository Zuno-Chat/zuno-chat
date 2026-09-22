import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/push/push_notification_codec.dart';

void main() {
  test('decodes a wrapped {"notification": {...}} payload', () {
    final bytes = utf8.encode(
      jsonEncode({
        'notification': {'event_id': '\$abc', 'room_id': '!room:example.org'},
      }),
    );
    final notification = pushNotificationFromMessageBytes(bytes);
    expect(notification?.eventId, '\$abc');
    expect(notification?.roomId, '!room:example.org');
  });

  test('decodes a bare, already-unwrapped notification object', () {
    final bytes = utf8.encode(
      jsonEncode({'event_id': '\$abc', 'room_id': '!room:example.org'}),
    );
    final notification = pushNotificationFromMessageBytes(bytes);
    expect(notification?.eventId, '\$abc');
    expect(notification?.roomId, '!room:example.org');
  });

  test('returns null for bytes that are not valid JSON', () {
    expect(pushNotificationFromMessageBytes(utf8.encode('not json')), isNull);
  });

  test('returns null for JSON that is not an object', () {
    expect(pushNotificationFromMessageBytes(utf8.encode('[1, 2, 3]')), isNull);
  });
}
