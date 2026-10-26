import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/notifications/messages/message_notification_content.dart';
import 'package:zuno/core/notifications/messages/message_notifications.dart';
import 'package:zuno/core/notifications/messages/notification_ids.dart';
import 'package:zuno/core/notifications/messages/notification_thread_store.dart';
import 'package:zuno/core/notifications/messages/notified_events_store.dart';
import 'package:zuno/core/notifications/settings/notification_preview.dart';
import 'package:zuno/core/notifications/settings/notification_sound_settings.dart';

import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/native_method_calls.dart';
import '../../../helpers/platform_capabilities.dart';
import '../../../helpers/test_clock.dart';

void main() {
  const roomId = '!room:example.org';
  final id = messageNotificationIdFor(roomId);
  late RecordedNotifications notifications;
  late Map<String, String> noticed;
  late RecordedMethodCalls conversations;
  final clockedTest = testsOnClock(() => DateTime(2031, 6, 1, 12));

  setUp(() {
    SharedPreferences.setMockInitialValues({messageToneEnabledKey: true});
    notifications = installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    noticed = {};
    conversations = installFakeConversationsChannel(noticed: noticed);
  });

  Future<void> post({String eventId = r'$e1', bool refine = false}) =>
      MessageNotifications.instance.showMessage(
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
        preview: NotificationPreview.full,
        refine: refine,
      );

  clockedTest(
    'a post over a native notice for the same event is a silent update',
    () async {
      noticed[roomId] = r'$e1';
      notifications.active = [
        {'id': id, 'channelId': 'direct_messages', 'payload': ''},
      ];

      await post();

      expect(conversations.takenNotices, ['$roomId/\$e1']);
      expect(notifications.single.id, id);
      expect(notifications.lastPlatformSpecifics['onlyAlertOnce'], isTrue);
    },
  );

  clockedTest('a post with no notice alerts as before', () async {
    await post();

    expect(conversations.takenNotices, ['$roomId/\$e1']);
    expect(notifications.lastPlatformSpecifics['onlyAlertOnce'], isFalse);
  });

  clockedTest('a notice for another event does not silence this one', () async {
    noticed[roomId] = r'$older';
    notifications.active = [
      {'id': id, 'channelId': 'direct_messages', 'payload': ''},
    ];

    await post();

    expect(notifications.lastPlatformSpecifics['onlyAlertOnce'], isFalse);
    expect(noticed, containsPair(roomId, r'$older'));
  });

  clockedTest(
    'a notice the user already dismissed does not silence the post',
    () async {
      noticed[roomId] = r'$e1';
      notifications.active = const [];

      await post();

      expect(conversations.takenNotices, ['$roomId/\$e1']);
      expect(notifications.lastPlatformSpecifics['onlyAlertOnce'], isFalse);
    },
  );

  clockedTest('where the platform posts no instant notices, nothing asks for '
      'one', () async {
    final service = MessageNotifications(
      capabilities: capabilitiesLike(
        androidCapabilities,
        instantPushNotices: false,
      ),
    );
    noticed[roomId] = r'$e1';

    expect(await service.takePushNotice(roomId, r'$e1'), isFalse);
    await service.retractPushNotice(roomId, r'$e1');
    await service.showMessage(
      MessageNotificationContent(
        roomId: roomId,
        title: 'Alice',
        body: 'hi',
        text: 'hi',
        eventId: r'$e1',
        isDirectChat: true,
        senderId: '@a:x',
        senderName: 'Alice',
        timestamp: DateTime.utc(2031),
      ),
      preview: NotificationPreview.full,
    );

    expect(conversations.takenNotices, isEmpty);
    expect(noticed, containsPair(roomId, r'$e1'));
  });

  clockedTest('a refine never consumes the notice', () async {
    noticed[roomId] = r'$e1';

    await post(refine: true);

    expect(conversations.takenNotices, isEmpty);
    expect(noticed, containsPair(roomId, r'$e1'));
  });

  clockedTest('a stale stored thread is dropped when the notice made the room '
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

  clockedTest(
    'a redelivered push retracts the notice it can no longer own',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await markEventNotifiedOnDisk(prefs, r'$e1');
      noticed[roomId] = r'$e1';
      notifications.active = [
        {'id': id, 'channelId': 'direct_messages', 'payload': ''},
      ];

      await post();

      expect(notifications.shown, isEmpty);
      expect(notifications.cancelled, [id]);
    },
  );

  clockedTest(
    'retractPushNotice cancels only the notice for that event',
    () async {
      await MessageNotifications.instance.retractPushNotice(roomId, r'$e1');
      expect(notifications.cancelled, isEmpty);

      noticed[roomId] = r'$e1';
      await MessageNotifications.instance.retractPushNotice(roomId, r'$other');
      expect(notifications.cancelled, isEmpty);

      await MessageNotifications.instance.retractPushNotice(roomId, r'$e1');
      expect(notifications.cancelled, [id]);
    },
  );
}
