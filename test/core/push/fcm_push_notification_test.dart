import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/push/fcm_push_notification.dart';

void main() {
  test('decodes Sygnal\'s event_id_only payload', () {
    final notification = pushNotificationFromFcmData({
      'event_id': '\$abc:example.org',
      'room_id': '!room:example.org',
      'prio': 'high',
    });
    expect(notification?.eventId, '\$abc:example.org');
    expect(notification?.roomId, '!room:example.org');
    expect(notification?.prio, 'high');
  });

  test('decodes stringified counts, which FCM cannot send as numbers', () {
    final notification = pushNotificationFromFcmData({
      'event_id': '\$abc:example.org',
      'room_id': '!room:example.org',
      'counts': '{"unread":3}',
    });
    expect(notification?.counts?.unread, 3);
  });

  test('refuses a payload with neither an event to fetch nor a badge', () {
    expect(
      pushNotificationFromFcmData({'room_id': '!room:example.org'}),
      isNull,
    );
    expect(
      pushNotificationFromFcmData({'event_id': '\$abc:example.org'}),
      isNull,
    );
    expect(pushNotificationFromFcmData(const {}), isNull);
  });

  test('decodes the flattened, stringified counts Sygnal\'s FCM v1 pushkin '
      'sends at the top level', () {
    final notification = pushNotificationFromFcmData({
      'event_id': '\$abc:example.org',
      'room_id': '!room:example.org',
      'unread': '3',
      'missed_calls': '1',
    });
    expect(notification?.eventId, '\$abc:example.org');
    expect(notification?.counts?.unread, 3);
    expect(notification?.counts?.missedCalls, 1);
  });

  test('keeps a badge-only push, which carries counts but no event', () {
    final notification = pushNotificationFromFcmData({'unread': '0'});
    expect(notification, isNotNull);
    expect(notification?.eventId, isNull);
    expect(notification?.roomId, isNull);
    expect(notification?.counts?.unread, 0);
  });

  test('a badge-only push with an unreadable count is still dropped', () {
    expect(pushNotificationFromFcmData({'unread': 'many'}), isNull);
  });

  test('survives a malformed counts value rather than taking the push '
      'down with it', () {
    final notification = pushNotificationFromFcmData({
      'event_id': '\$abc:example.org',
      'room_id': '!room:example.org',
      'counts': 'not json',
    });
    expect(notification?.eventId, '\$abc:example.org');
    expect(notification?.counts, isNull);
  });

  test('ignores non-string values without throwing', () {
    final notification = pushNotificationFromFcmData({
      'event_id': '\$abc:example.org',
      'room_id': '!room:example.org',
      'unexpected': 42,
    });
    expect(notification?.eventId, '\$abc:example.org');
  });
}
