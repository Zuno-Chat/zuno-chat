import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/notifications/message_notification_content.dart';
import 'package:zuno/core/notifications/notification_sound_player.dart';
import 'package:zuno/core/notifications/notification_sound_settings.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/platform_capabilities.dart';

const _roomId = '!room:example.org';

String _messagePayload(String roomId) =>
    jsonEncode({'type': 'message', 'roomId': roomId});

void main() {
  late RecordedNotifications notifications;
  late CallNotificationService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ambientCapabilities = iosCapabilities;
    notifications = installFakeLocalNotifications(platform: TargetPlatform.iOS);
    installSilentNotificationSideChannels();
    service = CallNotificationService(capabilities: iosCapabilities);
  });

  group('clearing', () {
    test('clearing every message notification takes down chats and rooms, '
        'and leaves the rest', () async {
      final otherRoom = messageNotificationIdFor('!other:example.org');
      notifications.active = [
        {
          'id': messageNotificationIdFor(_roomId),
          'payload': _messagePayload(_roomId),
        },
        {'id': otherRoom, 'payload': _messagePayload('!other:example.org')},
        {
          'id': 33,
          'payload': jsonEncode({'type': 'newDevice', 'deviceId': 'ABC'}),
        },
        {'id': null, 'payload': null},
      ];

      await service.cancelAllMessageNotifications();

      expect(
        notifications.cancelled,
        unorderedEquals([messageNotificationIdFor(_roomId), otherRoom]),
      );
    });

    test('a read chat that is showing is taken down, one that is not is left '
        'alone', () async {
      notifications.active = [
        {
          'id': messageNotificationIdFor(_roomId),
          'payload': _messagePayload(_roomId),
        },
      ];

      await service.cancelMessageNotificationsIfShowing([
        _roomId,
        '!gone:example.org',
      ]);

      expect(notifications.cancelled, [messageNotificationIdFor(_roomId)]);
    });
  });

  test('a message, a placeholder and their clean-up never ask iOS for an '
      'instant notice', () async {
    final conversations = installFakeConversationsChannel();
    const message = MessageNotificationContent(
      roomId: _roomId,
      title: 'Alice',
      body: 'hi',
      eventId: r'$1',
    );

    await service.showMessage(message, includeMessageActions: true);
    await service.showMessage(
      const MessageNotificationContent(
        roomId: _roomId,
        title: 'Alice',
        body: 'Tap to open',
        eventId: r'$2',
      ),
      placeholder: true,
    );
    await service.retractPlaceholder(_roomId, r'$2');
    await service.retractPushNotice(_roomId, r'$1');

    expect(await service.takePushNotice(_roomId, r'$1'), isFalse);
    expect(conversations.named('takePushNotice'), isEmpty);
  });

  group('posting', () {
    test(
      'a message is threaded by room and offers Reply and Mark as read',
      () async {
        await service.showMessage(
          const MessageNotificationContent(
            roomId: _roomId,
            title: 'Alice',
            body: 'hi',
            eventId: r'$1',
          ),
          includeMessageActions: true,
        );

        final ios = notifications.lastPlatformSpecifics;
        expect(ios['threadIdentifier'], _roomId);
        expect(ios['categoryIdentifier'], 'message');
      },
    );

    test('without an event to mark read, only Reply is offered', () async {
      await service.showMessage(
        const MessageNotificationContent(
          roomId: _roomId,
          title: 'New message',
          body: 'Tap to open',
        ),
        includeMessageActions: true,
      );

      expect(
        notifications.lastPlatformSpecifics['categoryIdentifier'],
        'reply',
      );
    });

    test(
      'without message actions, as for an invite, no action is offered',
      () async {
        await service.showMessage(
          const MessageNotificationContent(
            roomId: _roomId,
            title: 'Alice',
            body: 'invited you',
            eventId: r'$1',
          ),
        );

        expect(
          notifications.lastPlatformSpecifics['categoryIdentifier'],
          isNull,
        );
      },
    );

    group('alerting', () {
      var fakeNow = DateTime(2031);

      setUp(() {
        fakeNow = fakeNow.add(const Duration(days: 1));
        NotificationSoundPlayer.instance.now = () => fakeNow;
      });

      tearDown(() => NotificationSoundPlayer.instance.now = DateTime.now);

      const message = MessageNotificationContent(
        roomId: _roomId,
        title: 'Alice',
        body: 'hi',
        eventId: r'$1',
      );

      test('with the message tone on, a new message sounds and lights the '
          'screen', () async {
        SharedPreferences.setMockInitialValues({messageToneEnabledKey: true});

        await service.showMessage(message);

        final ios = notifications.lastPlatformSpecifics;
        expect(ios['presentSound'], isTrue);
        expect(ios['sound'], 'message_tone.caf');
        expect(ios['interruptionLevel'], 1);
      });

      test('a new message shows its banner while Zuno is open, and stays in '
          'the list', () async {
        SharedPreferences.setMockInitialValues({messageToneEnabledKey: true});

        await service.showMessage(message);

        final ios = notifications.lastPlatformSpecifics;
        expect(ios['presentBanner'], isTrue);
        expect(ios['presentAlert'], isTrue);
        expect(ios['presentList'], isTrue);
      });

      test('a quiet message never shows a banner while Zuno is open, but '
          'stays in the list', () async {
        SharedPreferences.setMockInitialValues({messageToneEnabledKey: true});

        await service.showMessage(
          const MessageNotificationContent(
            roomId: _roomId,
            title: 'Alice',
            body: 'hi',
            eventId: r'$1',
            quiet: true,
          ),
        );

        final ios = notifications.lastPlatformSpecifics;
        expect(ios['presentBanner'], isFalse);
        expect(ios['presentAlert'], isFalse);
        expect(ios['presentSound'], isFalse);
        expect(ios['sound'], isNull);
        expect(ios['presentList'], isTrue);
      });

      test('a second message in the same room inside the tone interval '
          'updates the list without a banner or sound', () async {
        SharedPreferences.setMockInitialValues({messageToneEnabledKey: true});
        await service.showMessage(message);
        notifications.active = [
          {
            'id': messageNotificationIdFor(_roomId),
            'payload': _messagePayload(_roomId),
          },
        ];

        await service.showMessage(
          const MessageNotificationContent(
            roomId: _roomId,
            title: 'Alice',
            body: 'and again',
            eventId: r'$2',
          ),
        );

        final ios = notifications.lastPlatformSpecifics;
        expect(ios['presentBanner'], isFalse);
        expect(ios['presentSound'], isFalse);
        expect(ios['sound'], isNull);
        expect(ios['presentList'], isTrue);
      });

      test('with the message tone off, a new message lights the screen '
          'without sound', () async {
        SharedPreferences.setMockInitialValues({messageToneEnabledKey: false});

        await service.showMessage(message);

        final ios = notifications.lastPlatformSpecifics;
        expect(ios['presentSound'], isFalse);
        expect(ios['sound'], isNull);
        expect(ios['interruptionLevel'], 1);
      });

      test('a quiet message goes to the list without sound or lighting the '
          'screen', () async {
        SharedPreferences.setMockInitialValues({messageToneEnabledKey: true});

        await service.showMessage(
          const MessageNotificationContent(
            roomId: _roomId,
            title: 'Alice',
            body: 'hi',
            eventId: r'$1',
            quiet: true,
          ),
        );

        final ios = notifications.lastPlatformSpecifics;
        expect(ios['presentSound'], isFalse);
        expect(ios['sound'], isNull);
        expect(ios['interruptionLevel'], 0);
      });

      test(
        'refining a message already on screen does not light it again',
        () async {
          SharedPreferences.setMockInitialValues({messageToneEnabledKey: true});
          await service.showMessage(message);
          notifications.active = [
            {
              'id': messageNotificationIdFor(_roomId),
              'payload': _messagePayload(_roomId),
            },
          ];

          await service.showMessage(
            const MessageNotificationContent(
              roomId: _roomId,
              title: 'Alice',
              body: 'hi, with the photo',
              eventId: r'$1',
            ),
            refine: true,
          );

          final ios = notifications.lastPlatformSpecifics;
          expect(notifications.shown.last.body, 'hi, with the photo');
          expect(ios['presentSound'], isFalse);
          expect(ios['sound'], isNull);
          expect(ios['interruptionLevel'], 0);
          expect(ios['presentBanner'], isFalse);
          expect(ios['presentAlert'], isFalse);
          expect(ios['presentList'], isTrue);
        },
      );
    });
  });

  test('startup registers the Reply and Mark as read actions, running in the '
      'background with no screen opened', () async {
    await service.initialize(claimDeclinePort: false);

    final categories = {
      for (final category
          in (notifications.initializeArguments!['notificationCategories']
                  as List)
              .cast<Map>())
        category['identifier']: [
          for (final action in (category['actions'] as List).cast<Map>())
            (
              action['identifier'],
              action['type'],
              (action['options'] as List).isEmpty,
            ),
        ],
    };
    expect(categories, {
      'message': [('reply', 'text', true), ('mark_read', 'plain', true)],
      'reply': [('reply', 'text', true)],
    });
  });
}
