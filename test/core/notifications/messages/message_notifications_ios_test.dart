import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/notifications/local_notifications.dart';
import 'package:zuno/core/notifications/messages/message_notification_content.dart';
import 'package:zuno/core/notifications/messages/message_notifications.dart';
import 'package:zuno/core/notifications/messages/notification_ids.dart';
import 'package:zuno/core/notifications/settings/notification_preview.dart';
import 'package:zuno/core/notifications/settings/notification_sound_settings.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/nse/opaque_thread_ids.dart';

import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/platform_capabilities.dart';
import '../../../helpers/test_clock.dart';

const _roomId = '!room:example.org';

String _messagePayload(String roomId) =>
    jsonEncode({'type': 'message', 'roomId': roomId});

MessageNotifications _messageNotifications(PlatformCapabilities capabilities) =>
    MessageNotifications(
      capabilities: capabilities,
      threadIds: OpaqueThreadIds(threadKey: (roomId) async => 'tok-$roomId'),
      notifications: LocalNotifications(capabilities: capabilities),
    );

void main() {
  late RecordedNotifications notifications;
  late MessageNotifications service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ambientCapabilities = iosCapabilities;
    notifications = installFakeLocalNotifications(platform: TargetPlatform.iOS);
    installSilentNotificationSideChannels();
    service = _messageNotifications(iosCapabilities);
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

    await service.showMessage(
      message,
      preview: NotificationPreview.full,
      isMessage: true,
    );
    await service.showMessage(
      const MessageNotificationContent(
        roomId: _roomId,
        title: 'Alice',
        body: 'Tap to open',
        eventId: r'$2',
      ),
      preview: NotificationPreview.full,
      placeholder: true,
    );
    await service.retractPlaceholder(
      _roomId,
      r'$2',
      preview: NotificationPreview.full,
    );
    await service.retractPushNotice(_roomId, r'$1');

    expect(await service.takePushNotice(_roomId, r'$1'), isFalse);
    expect(conversations.named('takePushNotice'), isEmpty);
  });

  group('posting', () {
    test('a message is threaded by its room token and offers Reply and Mark as '
        'read', () async {
      await service.showMessage(
        const MessageNotificationContent(
          roomId: _roomId,
          title: 'Alice',
          body: 'hi',
          eventId: r'$1',
        ),
        preview: NotificationPreview.full,
        isMessage: true,
      );

      final ios = notifications.lastPlatformSpecifics;
      expect(ios['threadIdentifier'], 'tok-$_roomId');
      expect(ios['categoryIdentifier'], 'message');
    });

    group('alerting', () {
      final clockedTest = testsOnClock(() => DateTime(2031));

      const message = MessageNotificationContent(
        roomId: _roomId,
        title: 'Alice',
        body: 'hi',
        eventId: r'$1',
      );

      clockedTest('with the message tone on, a new message sounds, lights the '
          'screen and shows its banner while Zuno is open, and stays in the '
          'list', () async {
        SharedPreferences.setMockInitialValues({messageToneEnabledKey: true});

        await service.showMessage(message, preview: NotificationPreview.full);

        final ios = notifications.lastPlatformSpecifics;
        expect(ios['presentSound'], isTrue);
        expect(ios['sound'], 'message_tone.caf');
        expect(ios['interruptionLevel'], 1);
        expect(ios['presentBanner'], isTrue);
        expect(ios['presentAlert'], isTrue);
        expect(ios['presentList'], isTrue);
      });

      clockedTest('a quiet message goes to the list without a banner, sound or '
          'lighting the screen', () async {
        SharedPreferences.setMockInitialValues({messageToneEnabledKey: true});

        await service.showMessage(
          const MessageNotificationContent(
            roomId: _roomId,
            title: 'Alice',
            body: 'hi',
            eventId: r'$1',
            quiet: true,
          ),
          preview: NotificationPreview.full,
        );

        final ios = notifications.lastPlatformSpecifics;
        expect(ios['presentBanner'], isFalse);
        expect(ios['presentAlert'], isFalse);
        expect(ios['presentSound'], isFalse);
        expect(ios['sound'], isNull);
        expect(ios['interruptionLevel'], 0);
        expect(ios['presentList'], isTrue);
      });

      clockedTest('a second message in the same room inside the tone interval '
          'updates the list without a banner or sound', () async {
        SharedPreferences.setMockInitialValues({messageToneEnabledKey: true});
        await service.showMessage(message, preview: NotificationPreview.full);
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
          preview: NotificationPreview.full,
        );

        final ios = notifications.lastPlatformSpecifics;
        expect(ios['presentBanner'], isFalse);
        expect(ios['presentSound'], isFalse);
        expect(ios['sound'], isNull);
        expect(ios['presentList'], isTrue);
      });

      clockedTest('with the message tone off, a new message lights the screen '
          'without sound', () async {
        SharedPreferences.setMockInitialValues({messageToneEnabledKey: false});

        await service.showMessage(message, preview: NotificationPreview.full);

        final ios = notifications.lastPlatformSpecifics;
        expect(ios['presentSound'], isFalse);
        expect(ios['sound'], isNull);
        expect(ios['interruptionLevel'], 1);
      });

      clockedTest(
        'refining a message already on screen does not light it again',
        () async {
          SharedPreferences.setMockInitialValues({messageToneEnabledKey: true});
          await service.showMessage(message, preview: NotificationPreview.full);
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
            preview: NotificationPreview.full,
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

  test('before native actions, startup registers the Reply and Mark as read '
      'actions, running in the background with no screen opened', () async {
    final flnOwned = LocalNotifications(
      capabilities: capabilitiesLike(
        iosCapabilities,
        nativeNotificationActions: false,
      ),
    );
    await flnOwned.initialize();

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
      'message_plain': <(Object?, Object?, bool)>[],
    });
  });

  test('the Darwin category follows the actions and whether there is an '
      'event to mark', () {
    expect(
      darwinMessageCategory(
        isMessage: true,
        offersActions: true,
        eventId: null,
      ),
      'reply',
    );
    expect(
      darwinMessageCategory(
        isMessage: true,
        offersActions: true,
        eventId: r'$1',
      ),
      'message',
    );
  });

  test('a message without actions still gets the category that hides its '
      'preview behind New message, and anything else gets none', () {
    expect(
      darwinMessageCategory(
        isMessage: true,
        offersActions: false,
        eventId: r'$1',
      ),
      'message_plain',
    );
    expect(
      darwinMessageCategory(
        isMessage: false,
        offersActions: false,
        eventId: r'$1',
      ),
      isNull,
    );
  });

  group('with native notification actions', () {
    final native = capabilitiesLike(
      iosCapabilities,
      nseNotifications: true,
      nativeNotificationActions: true,
    );
    const message = MessageNotificationContent(
      roomId: _roomId,
      title: 'Alice',
      body: 'hi',
      eventId: r'$1',
    );

    test('startup leaves the categories to native code', () async {
      await LocalNotifications(capabilities: native).initialize();

      expect(
        notifications.initializeArguments!['notificationCategories'],
        isEmpty,
      );
    });

    for (final (preview, category) in [
      (NotificationPreview.full, 'message'),
      (NotificationPreview.nameOnly, 'message_plain'),
      (NotificationPreview.nothing, 'message_plain'),
    ]) {
      test(
        'at ${preview.name}, a message gets the $category category',
        () async {
          await _messageNotifications(native)
              .showMessage(message, preview: preview, isMessage: true);

          expect(
            notifications.lastPlatformSpecifics['categoryIdentifier'],
            category,
          );
        },
      );
    }

    test('without native actions, the preview level still takes the '
        'actions away', () async {
      final beforeNative = capabilitiesLike(
        iosCapabilities,
        nseNotifications: true,
        nativeNotificationActions: false,
      );
      await _messageNotifications(beforeNative).showMessage(
        message,
        preview: NotificationPreview.nothing,
        isMessage: true,
      );

      expect(
        notifications.lastPlatformSpecifics['categoryIdentifier'],
        'message_plain',
      );
    });

    for (final preview in NotificationPreview.values) {
      test('at ${preview.name}, an invitation gets no category', () async {
        await _messageNotifications(native)
            .showMessage(message, preview: preview);

        expect(
          notifications.lastPlatformSpecifics['categoryIdentifier'],
          isNull,
        );
      });
    }

    test('taking back a placeholder re-posts the thread without actions at '
        'Name only', () async {
      const preview = NotificationPreview.nameOnly;
      final service = _messageNotifications(native);
      await service.showMessage(message, preview: preview, isMessage: true);
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
          body: 'Tap to open',
          eventId: r'$2',
        ),
        preview: preview,
        placeholder: true,
        isMessage: true,
      );

      await service.retractPlaceholder(_roomId, r'$2', preview: preview);

      expect(notifications.shown, hasLength(3));
      expect(
        notifications.lastPlatformSpecifics['categoryIdentifier'],
        'message_plain',
      );
    });
  });
}
