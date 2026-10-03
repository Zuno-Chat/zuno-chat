import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/notifications/message_notification_provider.dart';
import 'package:zuno/core/notifications/notification_avatar_cache.dart';
import 'package:zuno/core/notifications/notified_events_store.dart';
import 'package:zuno/core/notifications/notify_me.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

import '../../helpers/fake_local_notifications.dart';
import '../../helpers/fake_matrix.dart';
import '../../helpers/platform_capabilities.dart';

class _NotifyingClient extends Client {
  _NotifyingClient() : super('test', database: FakeDatabaseApi());

  @override
  String? prevBatch = 's1';

  @override
  PushruleEvaluator get pushruleEvaluator => PushruleEvaluator.fromRuleset(
    PushRuleSet(
      underride: [
        PushRule(
          ruleId: '.m.rule.message',
          default$: true,
          enabled: true,
          conditions: [
            PushCondition(
              kind: 'event_match',
              key: 'type',
              pattern: 'm.room.message',
            ),
          ],
          actions: ['notify'],
        ),
      ],
    ),
  );
}

void main() {
  late _NotifyingClient client;
  late Room room;
  late ProviderContainer container;
  late RecordedNotifications notifications;

  setUp(() async {
    notifications = installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    client = _NotifyingClient();
    client.setUserId('@me:x');
    room = buildTestRoom(client);
    room.setState(User('@a:x', displayName: 'Alice', room: room));
    room.setState(User('@me:x', displayName: 'Me', room: room));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    container.read(messageNotificationProvider);
  });

  Future<void> deliver(Event event) async {
    client.onTimelineEvent.add(event);
    await pumpEventQueue();
  }

  Event textEvent({
    String senderId = '@a:x',
    String body = 'hi',
    String type = EventTypes.Message,
    DateTime? originServerTs,
  }) => buildTestEvent(
    room,
    eventId: r'$1',
    senderId: senderId,
    type: type,
    originServerTs: originServerTs,
    content: {'msgtype': MessageTypes.Text, 'body': body},
  );

  test('posts a notification for someone else\'s message', () async {
    await deliver(textEvent(body: 'are you around?'));

    expect(notifications.shown.single.body, contains('are you around?'));
  });

  group('with mentions only', () {
    setUp(() async {
      await container
          .read(notifyMeProvider.notifier)
          .set(NotifyMe.mentionsOnly);
    });

    tearDown(
      () => TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );

    test('the app in front leaves other messages alone', () async {
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );

      await deliver(textEvent());

      expect(notifications.shown, isEmpty);
    });

    test('an app in the background shows other messages quietly, as a push '
        'would', () async {
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.paused,
      );

      await deliver(textEvent());

      expect(notifications.single.android['channelId'], 'quiet_messages');
    });

    test('an inactive app is no more in front than a background one', () async {
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.inactive,
      );

      await deliver(textEvent());

      expect(notifications.single.android['channelId'], 'quiet_messages');
    });
  });

  test('stays silent for a message you sent yourself', () async {
    await deliver(textEvent(senderId: '@me:x'));

    expect(notifications.shown, isEmpty);
  });

  test('still notifies for a message that arrived days late', () async {
    await deliver(
      textEvent(
        originServerTs: DateTime.now().subtract(const Duration(days: 2)),
      ),
    );

    expect(notifications.shown, hasLength(1));
  });

  test('ignores what the initial sync replays (no prevBatch yet), so a '
      'cache clear cannot notify weeks-old messages', () async {
    client.prevBatch = null;

    await deliver(textEvent(body: 'from weeks ago'));

    expect(notifications.shown, isEmpty);
  });

  test('skips an event a push already notified, so opening the app does '
      'not alert twice for the same message', () async {
    final prefs = await SharedPreferences.getInstance();
    await markEventNotifiedOnDisk(prefs, r'$1');

    await deliver(textEvent(body: 'already pushed'));

    expect(notifications.shown, isEmpty);
  });

  Event photoEvent({String caption = 'a cat'}) => buildTestEvent(
    room,
    eventId: r'$1',
    senderId: '@a:x',
    content: {
      'msgtype': MessageTypes.Image,
      'body': caption,
      'filename': 'cat.jpg',
      'url': 'mxc://x/cat',
    },
  );

  test(
    'posts a photo message by its caption, as a conversation line',
    () async {
      await deliver(photoEvent());

      final shown = notifications.shown.singleWhere((n) => n.id != 4004);
      expect(shown.body, contains('a cat'));
      expect(shown.android['style'], AndroidNotificationStyle.messaging.index);
    },
  );

  group('read elsewhere', () {
    late int roomNotificationId;

    setUp(() => roomNotificationId = messageNotificationIdFor(room.id));

    Future<void> syncWithCount(int count) async {
      client.onSync.add(
        SyncUpdate(
          nextBatch: 's2',
          rooms: RoomsUpdate(
            join: {
              room.id: JoinedRoomUpdate(
                unreadNotifications: UnreadNotificationCounts(
                  notificationCount: count,
                ),
              ),
            },
          ),
        ),
      );
      await pumpEventQueue();
    }

    void showRoomNotification() {
      notifications.active = [
        {
          'id': roomNotificationId,
          'channelId': 'direct_messages',
          'payload': '',
        },
      ];
    }

    test('takes the room notification down once a sync says nothing is '
        'unread there', () async {
      await deliver(textEvent(body: 'hi'));
      showRoomNotification();

      await syncWithCount(0);

      expect(notifications.cancelled, contains(roomNotificationId));
    });

    test('leaves the room alone while it still has unread messages', () async {
      await deliver(textEvent(body: 'hi'));
      showRoomNotification();

      await syncWithCount(2);

      expect(notifications.cancelled, isEmpty);
    });

    test('a room read elsewhere is taken down after the post of that same '
        'sync lands, never before it', () async {
      final gate = Completer<void>();
      NotificationAvatarCache.instance = NotificationAvatarCache(
        directory: () async {
          await gate.future;
          throw const FileSystemException('held');
        },
      );
      addTearDown(
        () => NotificationAvatarCache.instance = NotificationAvatarCache(),
      );
      room.setState(
        User(
          '@a:x',
          displayName: 'Alice',
          avatarUrl: 'mxc://x/alice',
          room: room,
        ),
      );
      showRoomNotification();

      client.onTimelineEvent.add(textEvent(body: 'read on the laptop'));
      await syncWithCount(0);
      gate.complete();
      await pumpEventQueue();

      final methods = notifications.methods;
      expect(methods, contains('show'));
      expect(
        methods.lastIndexOf('cancel'),
        greaterThan(methods.lastIndexOf('show')),
      );
    });

    group('with Apple push', () {
      const channel = MethodChannel('zuno/apns');
      TestDefaultBinaryMessenger messenger() =>
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      late List<MethodCall> apnsCalls;
      late List<int> cancelledWhenAppleWasAsked;

      setUp(() {
        apnsCalls = [];
        cancelledWhenAppleWasAsked = [];
        messenger().setMockMethodCallHandler(channel, (call) async {
          apnsCalls.add(call);
          cancelledWhenAppleWasAsked = [...notifications.cancelled];
          return 1;
        });
        addTearDown(() => messenger().setMockMethodCallHandler(channel, null));
      });

      test(
        'a read room also loses the alerts Apple delivered for it',
        () async {
          ambientCapabilities = iosCapabilities;

          await syncWithCount(0);

          expect(apnsCalls.single.method, 'removeDelivered');
          expect(apnsCalls.single.arguments, {
            'roomIds': [room.id],
          });
        },
      );

      test('a room with unread messages keeps its alerts', () async {
        ambientCapabilities = iosCapabilities;

        await syncWithCount(2);

        expect(apnsCalls, isEmpty);
      });

      test('Android never asks for Apple alerts to be removed', () async {
        ambientCapabilities = androidCapabilities;

        await syncWithCount(0);

        expect(apnsCalls, isEmpty);
      });

      test('the local notification comes down after Apple was asked, never '
          'before', () async {
        ambientCapabilities = iosCapabilities;
        showRoomNotification();

        await syncWithCount(0);

        expect(apnsCalls.single.method, 'removeDelivered');
        expect(notifications.cancelled, contains(roomNotificationId));
        expect(cancelledWhenAppleWasAsked, isEmpty);
      });

      test('the local notification still comes down when Apple cannot remove '
          'its alerts', () async {
        ambientCapabilities = iosCapabilities;
        messenger().setMockMethodCallHandler(channel, (call) async {
          apnsCalls.add(call);
          throw PlatformException(code: 'unavailable');
        });
        showRoomNotification();

        await syncWithCount(0);

        expect(apnsCalls.single.method, 'removeDelivered');
        expect(notifications.cancelled, contains(roomNotificationId));
      });
    });

    test('does nothing for a room with no notification showing', () async {
      notifications.active = const [];

      await syncWithCount(0);

      expect(notifications.cancelled, isEmpty);
    });
  });
}
