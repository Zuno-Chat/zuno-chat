import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_store.dart';
import 'package:zuno/core/calls/notifications/ringing_call_store.dart';
import 'package:zuno/core/notifications/messages/notification_room_cache.dart';
import 'package:zuno/core/notifications/messages/notification_thread_store.dart';
import 'package:zuno/core/notifications/settings/notification_preview.dart';
import 'package:zuno/core/notifications/settings/notification_sound_settings.dart';
import 'package:zuno/core/notifications/settings/notify_me.dart';
import 'package:zuno/core/push/diagnostics/push_delivery_log.dart';
import 'package:zuno/core/push/fcm/fcm_registration_store.dart';

import '../../helpers/fixtures.dart';

void main() {
  final store = pushFixture('flutter_store_v1.json');
  final keys = (store['keys'] as Map).cast<String, String>();
  final values = (store['values'] as Map).cast<String, String>();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('every key native code reads or writes is the key the app uses', () {
    expect({
      'ringingCall': ringingCallKey,
      'resolvedCallPrefix': resolvedCallKeyPrefix,
      'roomCache': notificationRoomCacheKey,
      'threads': notificationThreadsKey,
      'recentDeliveries': pushDeliveryLogKey,
      'fcmToken': fcmTokenKey,
      'notificationPreview': notificationPreviewKey,
      'notifyMe': notifyMePreferenceKey,
      'messageTone': messageToneEnabledKey,
      'messageVibration': messageVibrationEnabledKey,
      'ringtone': ringtoneEnabledKey,
      'callVibration': callVibrationEnabledKey,
    }, keys);
  });

  test('the settings native code checks are stored as it expects', () {
    expect(NotificationPreview.nothing.name, values['previewHidden']);
    expect(NotifyMe.mentionsOnly.name, values['notifyMeMentionsOnly']);
  });

  group('the ringing call record', () {
    final ringing = (store['ringingCall'] as Map).cast<String, Object?>();
    final postedAt = DateTime.fromMillisecondsSinceEpoch(
      ringing['postedAt']! as int,
    );

    test('reads the record native code writes', () async {
      SharedPreferences.setMockInitialValues({
        keys['ringingCall']!: jsonEncode(ringing),
      });
      final prefs = await SharedPreferences.getInstance();

      final read = withClock(
        Clock.fixed(postedAt),
        () => readRingingCall(prefs),
      );

      expect(read, (
        roomId: ringing['roomId'],
        callId: ringing['callId'],
        callerId: ringing['callerId'],
        isVideo: ringing['isVideo'],
      ));
    });
  });

  test('a resolved call is stored under its id, at the time in '
      'milliseconds', () async {
    final resolved = (store['resolvedCall'] as Map).cast<String, Object?>();
    final callId = resolved['callId']! as String;
    final at = resolved['at']! as int;
    final prefs = await SharedPreferences.getInstance();

    await withClock(
      Clock.fixed(DateTime.fromMillisecondsSinceEpoch(at)),
      () => markCallResolvedOnDisk(prefs, callId),
    );

    expect(prefs.getInt('${keys['resolvedCallPrefix']}$callId'), at);
  });

  test('the room cache is encoded as native code parses it', () {
    final cache = (store['roomCache'] as Map).cast<String, Object?>();
    final rooms = [
      for (final room in (cache['rooms']! as List).cast<Map>())
        (
          id: room['id'] as String,
          name: room['name'] as String,
          isDirect: room['isDirect'] as bool,
        ),
    ];

    expect(encodeNotificationRoomCache(rooms), cache['encoded']);
  });

  test('a delivery line native code writes reads back', () {
    final delivery = (store['delivery'] as Map).cast<String, Object?>();

    final record = parsePushDeliveryLog(delivery['line']! as String).single;

    expect(
      record.receivedAt,
      DateTime.fromMillisecondsSinceEpoch(delivery['receivedAtMs']! as int),
    );
    expect(
      record.sentAt,
      DateTime.fromMillisecondsSinceEpoch(delivery['sentAtMs']! as int),
    );
    expect(record.originalPriority, delivery['originalPriority']);
    expect(record.deliveredPriority, delivery['deliveredPriority']);
    expect(record.deviceIdle, delivery['deviceIdle']);
    expect(record.standbyBucket, delivery['standbyBucket']);
  });

  test('the FCM token native code reads is stored under its key', () async {
    final prefs = await SharedPreferences.getInstance();

    await saveFcmRegistration(prefs, token: 'token-abc');

    expect(prefs.getString(keys['fcmToken']!), 'token-abc');
  });
}
