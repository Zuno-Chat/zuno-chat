import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/notifications/message_notification_content.dart';
import 'package:zuno/core/notifications/notification_sound_player.dart';
import 'package:zuno/core/notifications/notification_sound_settings.dart';
import 'package:zuno/core/notifications/notification_thread_store.dart';
import 'package:zuno/core/notifications/notified_events_store.dart';

import '../../helpers/fake_local_notifications.dart';

void main() {
  const roomId = '!room:example.org';
  final id = messageNotificationIdFor(roomId);
  late RecordedNotifications notifications;
  late Map<String, String> noticed;
  late List<String> taken;
  var fakeNow = DateTime(2031, 6, 1, 12);

  setUp(() {
    fakeNow = fakeNow.add(const Duration(days: 1));
    NotificationSoundPlayer.instance.now = () => fakeNow;
    SharedPreferences.setMockInitialValues({messageToneEnabledKey: true});
    notifications = installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    noticed = {};
    taken = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('zuno/conversations'), (
          call,
        ) async {
          if (call.method != 'takePushNotice') return null;
          final args = (call.arguments as Map).cast<String, Object?>();
          final room = args['roomId'] as String;
          taken.add('$room/${args['eventId']}');
          if (noticed[room] != args['eventId']) return false;
          noticed.remove(room);
          return true;
        });
  });

  tearDown(() {
    NotificationSoundPlayer.instance.now = DateTime.now;
  });

  Future<void> post({String eventId = r'$e1', bool refine = false}) =>
      CallNotificationService.instance.showMessage(
        MessageNotificationContent(
          roomId: roomId,
          title: 'Alice',
          body: 'hi',
          text: 'hi',
          eventId: eventId,
          isDirectChat: true,
          senderId: '@a:x',
          senderName: 'Alice',
          timestamp: DateTime.utc(2031),
        ),
        refine: refine,
      );

  test(
    'a post over a native notice for the same event is a silent update',
    () async {
      noticed[roomId] = r'$e1';
      notifications.active = [
        {'id': id, 'channelId': 'direct_messages', 'payload': ''},
      ];

      await post();

      expect(taken, ['$roomId/\$e1']);
      expect(notifications.single.id, id);
      expect(notifications.lastPlatformSpecifics['onlyAlertOnce'], isTrue);
    },
  );

  test('a post with no notice alerts as before', () async {
    await post();

    expect(taken, ['$roomId/\$e1']);
    expect(notifications.lastPlatformSpecifics['onlyAlertOnce'], isFalse);
  });

  test('a notice for another event does not silence this one', () async {
    noticed[roomId] = r'$older';
    notifications.active = [
      {'id': id, 'channelId': 'direct_messages', 'payload': ''},
    ];

    await post();

    expect(notifications.lastPlatformSpecifics['onlyAlertOnce'], isFalse);
    expect(noticed, containsPair(roomId, r'$older'));
  });

  test(
    'a notice the user already dismissed does not silence the post',
    () async {
      noticed[roomId] = r'$e1';
      notifications.active = const [];

      await post();

      expect(taken, ['$roomId/\$e1']);
      expect(notifications.lastPlatformSpecifics['onlyAlertOnce'], isFalse);
    },
  );

  test('a refine never consumes the notice', () async {
    noticed[roomId] = r'$e1';

    await post(refine: true);

    expect(taken, isEmpty);
    expect(noticed, containsPair(roomId, r'$e1'));
  });

  test('a stale stored thread is dropped when the notice made the room '
      'look like it was showing', () async {
    final prefs = await SharedPreferences.getInstance();
    await writeNotificationThread(
      prefs,
      NotificationThread(
        roomId: roomId,
        title: 'Alice',
        isGroupChat: false,
        lines: [
          NotificationLine(
            eventId: r'$old',
            senderId: '@a:x',
            senderName: 'Alice',
            text: 'yesterday',
            timestamp: DateTime.utc(2030),
          ),
        ],
      ),
    );
    noticed[roomId] = r'$e1';
    notifications.active = [
      {'id': id, 'channelId': 'direct_messages', 'payload': ''},
    ];

    await post();

    final thread = readNotificationThread(prefs, roomId)!;
    expect(thread.lines.map((l) => l.eventId), [r'$e1']);
  });

  test('a redelivered push retracts the notice it can no longer own', () async {
    final prefs = await SharedPreferences.getInstance();
    await markEventNotifiedOnDisk(prefs, r'$e1');
    noticed[roomId] = r'$e1';
    notifications.active = [
      {'id': id, 'channelId': 'direct_messages', 'payload': ''},
    ];

    await post();

    expect(notifications.shown, isEmpty);
    expect(notifications.cancelled, [id]);
  });

  test('retractPushNotice cancels only the notice for that event', () async {
    await CallNotificationService.instance.retractPushNotice(roomId, r'$e1');
    expect(notifications.cancelled, isEmpty);

    noticed[roomId] = r'$e1';
    await CallNotificationService.instance.retractPushNotice(roomId, r'$other');
    expect(notifications.cancelled, isEmpty);

    await CallNotificationService.instance.retractPushNotice(roomId, r'$e1');
    expect(notifications.cancelled, [id]);
  });
}
