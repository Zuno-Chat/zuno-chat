import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/notifications/local_notifications.dart';
import 'package:zuno/core/notifications/messages/message_notification_content.dart';
import 'package:zuno/core/notifications/messages/message_notifications.dart';
import 'package:zuno/core/notifications/messages/notification_sound_player.dart';
import 'package:zuno/core/notifications/messages/notified_events_store.dart';
import 'package:zuno/core/notifications/settings/notification_preview.dart';
import 'package:zuno/core/notifications/settings/notification_sound_settings.dart';

import '../../../helpers/fake_local_notifications.dart';

void main() {
  group('silencedMessageChannels', () {
    AndroidNotificationChannel channel(String id, Importance importance) =>
        AndroidNotificationChannel(id, 'Name $id', importance: importance);

    test('names a chat channel the user turned down or off', () {
      expect(
        silencedMessageChannels([
          channel(messagesChannelId, Importance.low),
          channel('group_messages', Importance.none),
        ]).map((c) => c.id),
        [messagesChannelId, 'group_messages'],
      );
    });

    test('ignores channels still at a sounding level', () {
      expect(
        silencedMessageChannels([
          channel(messagesChannelId, Importance.high),
          channel('group_messages', Importance.defaultImportance),
        ]),
        isEmpty,
      );
    });

    test('ignores the quiet channel, which is low on purpose, and non-chat '
        'channels', () {
      expect(
        silencedMessageChannels([
          channel('quiet_messages', Importance.low),
          channel('background_sync', Importance.min),
        ]),
        isEmpty,
      );
    });
  });

  group('showMessage sound channel', () {
    var fakeNow = DateTime(2031);

    setUp(() {
      fakeNow = fakeNow.add(const Duration(days: 1));
      NotificationSoundPlayer.instance.now = () => fakeNow;
    });

    tearDown(() => NotificationSoundPlayer.instance.now = DateTime.now);

    test('posts an alerting notification on the messages channel when the '
        'message tone setting is on', () async {
      SharedPreferences.setMockInitialValues({messageToneEnabledKey: true});
      final notifications = installFakeLocalNotifications();
      installSilentNotificationSideChannels();

      await MessageNotifications.instance.showMessage(
        const MessageNotificationContent(
          roomId: '!room:example.org',
          title: 'Alice',
          body: 'hi',
        ),
        preview: NotificationPreview.full,
      );

      final specifics = notifications.lastPlatformSpecifics;
      expect(specifics['channelId'], messagesChannelId);
      expect(specifics['channelName'], 'Chat messages');
      expect(specifics['silent'], isFalse);
      expect(specifics['onlyAlertOnce'], isFalse);
    });

    test('posts a silent notification on the same channel when the message '
        'tone setting is off', () async {
      SharedPreferences.setMockInitialValues({messageToneEnabledKey: false});
      final notifications = installFakeLocalNotifications();
      installSilentNotificationSideChannels();

      await MessageNotifications.instance.showMessage(
        const MessageNotificationContent(
          roomId: '!room:example.org',
          title: 'Alice',
          body: 'hi',
        ),
        preview: NotificationPreview.full,
      );

      final specifics = notifications.lastPlatformSpecifics;
      expect(specifics['channelId'], messagesChannelId);
      expect(specifics['silent'], isTrue);
    });

    test(
      'posts a group message on the group channel, not the direct one',
      () async {
        SharedPreferences.setMockInitialValues({messageToneEnabledKey: true});
        final notifications = installFakeLocalNotifications();
        installSilentNotificationSideChannels();

        await MessageNotifications.instance.showMessage(
          const MessageNotificationContent(
            roomId: '!room:example.org',
            title: 'A group',
            body: 'hi',
            isDirectChat: false,
          ),
          preview: NotificationPreview.full,
        );

        final specifics = notifications.lastPlatformSpecifics;
        expect(specifics['channelId'], 'group_messages');
        expect(specifics['channelName'], 'Room messages');
        expect(specifics['silent'], isFalse);
      },
    );

    test('a second message in the same room within the rate limit is an '
        'only-alert-once update, not a silent one, so Android mutes it '
        'instead of cutting off the tone still playing', () async {
      SharedPreferences.setMockInitialValues({messageToneEnabledKey: true});
      final notifications = installFakeLocalNotifications();
      installSilentNotificationSideChannels();

      await MessageNotifications.instance.showMessage(
        const MessageNotificationContent(
          roomId: '!room:example.org',
          title: 'Alice',
          body: 'hi',
        ),
        preview: NotificationPreview.full,
      );
      await MessageNotifications.instance.showMessage(
        const MessageNotificationContent(
          roomId: '!room:example.org',
          title: 'Alice',
          body: 'are you there?',
        ),
        preview: NotificationPreview.full,
      );

      expect(notifications.shown, hasLength(2));
      expect(notifications.shown.first.android['onlyAlertOnce'], isFalse);
      final specifics = notifications.lastPlatformSpecifics;
      expect(specifics['channelId'], messagesChannelId);
      expect(specifics['onlyAlertOnce'], isTrue);
      expect(specifics['silent'], isFalse);
    });
  });

  test(
    'the buzz follows the post, so the channel tone is never behind it',
    () async {
      SharedPreferences.setMockInitialValues({
        messageToneEnabledKey: true,
        messageVibrationEnabledKey: true,
      });
      final notifications = installFakeLocalNotifications();
      installSilentNotificationSideChannels();
      NotificationSoundPlayer.instance.now = () => DateTime(2031, 3);
      addTearDown(() => NotificationSoundPlayer.instance.now = DateTime.now);
      const vibration = MethodChannel('zuno/vibration');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(vibration, (call) async {
        notifications.methods.add(call.method);
        return call.method == 'hasVibrator' ? true : null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(vibration, null));

      await MessageNotifications.instance.showMessage(
        const MessageNotificationContent(
          roomId: '!room:example.org',
          title: 'Alice',
          body: 'hi',
        ),
        preview: NotificationPreview.full,
      );

      expect(notifications.methods, containsAllInOrder(['show', 'vibrate']));
    },
  );

  group('showMessage dedupe', () {
    var fakeNow = DateTime(2031, 6);
    late RecordedNotifications notifications;

    setUp(() {
      fakeNow = fakeNow.add(const Duration(days: 1));
      NotificationSoundPlayer.instance.now = () => fakeNow;
      SharedPreferences.setMockInitialValues({messageToneEnabledKey: true});
      notifications = installFakeLocalNotifications();
      installSilentNotificationSideChannels();
    });

    tearDown(() => NotificationSoundPlayer.instance.now = DateTime.now);

    Future<void> post({String roomId = '!room:example.org', String? eventId}) =>
        MessageNotifications.instance.showMessage(
          MessageNotificationContent(
            roomId: roomId,
            title: 'Alice',
            body: 'hi',
            eventId: eventId,
          ),
          preview: NotificationPreview.full,
        );

    test('skips an event it already notified, so a sync catch-up cannot '
        're-alert what a push already showed', () async {
      await post(eventId: r'$e1');
      await post(eventId: r'$e1');

      expect(notifications.shown, hasLength(1));
    });

    test('skips an event another isolate already notified', () async {
      await markEventNotifiedOnDisk(
        await SharedPreferences.getInstance(),
        r'$pushed',
      );

      await post(eventId: r'$pushed');

      expect(notifications.shown, isEmpty);
    });

    test('a different event in the same room still posts', () async {
      await post(eventId: r'$e1');
      await post(eventId: r'$e2');

      expect(notifications.shown, hasLength(2));
    });

    test('a post without an eventId is never deduped', () async {
      await post();
      await post();

      expect(notifications.shown, hasLength(2));
    });

    test('a skipped post does not take the tone slot, so the next room '
        'still alerts', () async {
      await post(eventId: r'$e1');
      fakeNow = fakeNow.add(const Duration(seconds: 3));
      await post(eventId: r'$e1');
      await post(roomId: '!other:example.org', eventId: r'$e2');

      expect(notifications.shown, hasLength(2));
      final specifics = notifications.lastPlatformSpecifics;
      expect(specifics['silent'], isFalse);
      expect(specifics['onlyAlertOnce'], isFalse);
    });
  });

  group('showMessage actions', () {
    late RecordedNotifications notifications;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      notifications = installFakeLocalNotifications();
      installSilentNotificationSideChannels();
    });

    List<Map<String, Object?>> actionsOf(Map<String, Object?> android) =>
        (android['actions'] as List? ?? const [])
            .cast<Map>()
            .map((a) => a.cast<String, Object?>())
            .toList();

    test('attaches no actions by default — invites and the unresolved-push '
        'fallback share this method and neither is a room worth replying to '
        'sight unseen', () async {
      await MessageNotifications.instance.showMessage(
        const MessageNotificationContent(
          roomId: '!room:example.org',
          title: 'Alice',
          body: 'hi',
          eventId: r'$1',
        ),
        preview: NotificationPreview.full,
      );

      expect(actionsOf(notifications.lastPlatformSpecifics), isEmpty);
    });

    test('attaches Reply and Mark as read for a genuine message', () async {
      await MessageNotifications.instance.showMessage(
        const MessageNotificationContent(
          roomId: '!room:example.org',
          title: 'Alice',
          body: 'hi',
          eventId: r'$1',
        ),
        preview: NotificationPreview.full,
        isMessage: true,
      );

      final actions = actionsOf(notifications.lastPlatformSpecifics);
      expect(actions.map((a) => a['id']), containsAll(['reply', 'mark_read']));
      final reply = actions.singleWhere((a) => a['id'] == 'reply');
      expect(reply['showsUserInterface'], isFalse);
      expect(reply['cancelNotification'], isTrue);
      expect((reply['inputs'] as List), isNotEmpty);
      expect(reply['allowGeneratedReplies'], isFalse);
    });

    test('omits Mark as read (but keeps Reply) when there is no eventId '
        'to point setReadMarker at', () async {
      await MessageNotifications.instance.showMessage(
        const MessageNotificationContent(
          roomId: '!room:example.org',
          title: 'New message',
          body: 'Tap to open',
        ),
        preview: NotificationPreview.full,
        isMessage: true,
      );

      final actions = actionsOf(notifications.lastPlatformSpecifics);
      expect(actions.map((a) => a['id']), ['reply']);
    });

    test('the payload carries eventId only when given', () async {
      for (final eventId in [r'$1', null]) {
        await MessageNotifications.instance.showMessage(
          MessageNotificationContent(
            roomId: '!room:example.org',
            title: 'Alice',
            body: 'hi',
            eventId: eventId,
          ),
          preview: NotificationPreview.full,
          isMessage: true,
        );

        expect(jsonDecode(notifications.shown.last.payload), {
          'type': 'message',
          'roomId': '!room:example.org',
          'eventId': ?eventId,
        });
      }
    });
  });

  group('cancelAllMessageNotifications', () {
    late RecordedNotifications notifications;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      notifications = installFakeLocalNotifications();
      installSilentNotificationSideChannels();
    });

    test('takes down every chat notification but leaves the ring and the '
        'security alert alone', () async {
      notifications.active = [
        {'id': 11, 'channelId': 'direct_messages', 'payload': '{}'},
        {'id': 22, 'channelId': 'group_messages', 'payload': '{}'},
        {'id': 4002, 'channelId': 'calls_ringing', 'payload': '{}'},
        {'id': 33, 'channelId': 'security', 'payload': '{}'},
      ];

      await MessageNotifications.instance.cancelAllMessageNotifications();

      expect(notifications.cancelled, unorderedEquals([11, 22]));
    });
  });
}
