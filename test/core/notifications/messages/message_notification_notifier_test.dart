import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/notifications/messages/message_notification_provider.dart';
import 'package:zuno/core/notifications/messages/notification_avatar_cache.dart';
import 'package:zuno/core/notifications/messages/notified_events_store.dart';
import 'package:zuno/core/notifications/settings/notify_me.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/nse/opaque_thread_ids.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

import '../../../helpers/fake_calls_channel.dart';
import '../../../helpers/fake_encryption.dart';
import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/native_method_calls.dart';
import '../../../helpers/notifying_client.dart';
import '../../../helpers/platform_capabilities.dart';
import '../../../helpers/preferences_container.dart';

class _DecryptingClient extends NotifyingClient {
  final decryption = FakeRoomDecryption();

  @override
  Encryption? get encryption => decryption;

  @override
  PushruleEvaluator get pushruleEvaluator => PushruleEvaluator.fromRuleset(
    PushRuleSet(
      underride: [
        for (final type in [EventTypes.Message, EventTypes.Encrypted])
          PushRule(
            ruleId: type,
            default$: true,
            enabled: true,
            conditions: [
              PushCondition(kind: 'event_match', key: 'type', pattern: type),
            ],
            actions: ['notify'],
          ),
      ],
    ),
  );
}

void main() {
  late _DecryptingClient client;
  late Room room;
  late ProviderContainer container;
  late RecordedNotifications notifications;

  setUp(() async {
    notifications = installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    client = _DecryptingClient();
    client.setUserId('@me:x');
    room = buildTestRoom(client);
    room.setState(User('@a:x', displayName: 'Alice', room: room));
    room.setState(User('@me:x', displayName: 'Me', room: room));
    container = await containerWithPreferences(
      {},
      overrides: [matrixClientProvider.overrideWithValue(client)],
    );
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

  test('a message read elsewhere in the same sync is taken down after it '
      'posts, never before', () async {
    client.rooms.add(room..membership = Membership.join);
    client.onSync.add(SyncUpdate(nextBatch: 's1'));
    await pumpEventQueue();
    notifications.active = [
      {
        'id': messageNotificationIdFor(room.id),
        'channelId': 'direct_messages',
        'payload': '',
      },
    ];

    client.onTimelineEvent.add(textEvent(body: 'read on the laptop'));
    client.onSync.add(
      SyncUpdate(
        nextBatch: 's2',
        rooms: RoomsUpdate(
          join: {
            room.id: JoinedRoomUpdate(
              unreadNotifications: UnreadNotificationCounts(
                notificationCount: 0,
              ),
            ),
          },
        ),
      ),
    );
    await pumpEventQueue();

    final methods = notifications.methods;
    expect(methods, contains('show'));
    expect(
      methods.lastIndexOf('cancel'),
      greaterThan(methods.lastIndexOf('show')),
    );
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

      final shown = notifications.single;
      expect(shown.body, contains('a cat'));
      expect(shown.android['style'], AndroidNotificationStyle.messaging.index);
    },
  );

  group('a message whose key has not arrived yet', () {
    Event locked({String senderId = '@a:x', String sessionId = 'session'}) =>
        buildTestEvent(
          room,
          eventId: r'$1',
          senderId: senderId,
          type: EventTypes.Encrypted,
          content: {
            'algorithm': AlgorithmTypes.megolmV1AesSha2,
            'session_id': sessionId,
            'ciphertext': 'sealed',
            'msgtype': MessageTypes.BadEncrypted,
            'can_request_session': true,
          },
        );

    List<String?> linesOf(ShownNotification shown) => [
      for (final message
          in ((shown.android['styleInformation'] as Map)['messages'] as List)
              .cast<Map>())
        message['text'] as String?,
    ];

    Future<void> keyArrives([String sessionId = 'session']) async {
      room.onSessionKeyReceived.add(sessionId);
      await pumpEventQueue();
    }

    test('in a chat, is named after the partner as stored, not their '
        'username', () async {
      final dm = buildTestRoom(client, id: '!dm:x')
        ..membership = Membership.join;
      client.rooms.add(dm);
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: {
          '@test2:x': ['!dm:x'],
        },
      );
      (client.database as StoredMembersFakeDatabaseApi)
              .displayNames['@test2:x'] =
          'George';

      await deliver(
        buildTestEvent(
          dm,
          eventId: r'$dm',
          senderId: '@test2:x',
          type: EventTypes.Encrypted,
          content: {
            'algorithm': AlgorithmTypes.megolmV1AesSha2,
            'session_id': 'session',
            'ciphertext': 'sealed',
            'msgtype': MessageTypes.BadEncrypted,
            'can_request_session': true,
          },
        ),
      );

      expect(notifications.single.title, 'George');
      expect(linesOf(notifications.single), ['New message']);
    });

    test('still shows, as "New message" in its room', () async {
      await deliver(locked());

      expect(linesOf(notifications.single), ['New message']);
    });

    test('once its key arrives, the message takes that line\'s place without '
        'alerting again', () async {
      await deliver(locked());
      notifications.active = [
        {
          'id': messageNotificationIdFor(room.id),
          'channelId': 'direct_messages',
          'payload': '',
        },
      ];
      client.decryption.decrypted.add(textEvent(body: 'are you around?'));

      await keyArrives();

      final refined = notifications.shown.last;
      expect(refined.id, messageNotificationIdFor(room.id));
      expect(linesOf(refined), ['are you around?']);
      expect(refined.android['onlyAlertOnce'], isTrue);
    });

    test('a key for another conversation leaves it waiting', () async {
      await deliver(locked());

      await keyArrives('another');

      expect(client.decryption.attempts, 0);
      expect(notifications.shown, hasLength(1));
    });

    test('a message that turns out to need no notification takes the line '
        'down', () async {
      await deliver(locked());
      client.decryption.decrypted.add(
        buildTestEvent(
          room,
          eventId: r'$1',
          senderId: '@a:x',
          content: {
            'msgtype': MessageTypes.Text,
            'body': '* fixed',
            'm.relates_to': {'rel_type': 'm.replace', 'event_id': r'$0'},
          },
        ),
      );

      await keyArrives();

      expect(notifications.cancelled, [messageNotificationIdFor(room.id)]);
    });

    test('is not waited on once its room is read', () async {
      await deliver(locked());
      client.onSync.add(
        SyncUpdate(
          nextBatch: 's2',
          rooms: RoomsUpdate(
            join: {
              room.id: JoinedRoomUpdate(
                unreadNotifications: UnreadNotificationCounts(
                  notificationCount: 0,
                ),
              ),
            },
          ),
        ),
      );
      await pumpEventQueue();

      await keyArrives();

      expect(client.decryption.attempts, 0);
      expect(notifications.shown, hasLength(1));
    });

    test('is not shown when you sent it yourself', () async {
      await deliver(locked(senderId: '@me:x'));
      await keyArrives();

      expect(notifications.shown, isEmpty);
      expect(client.decryption.attempts, 0);
    });

    test('is no longer waited on after five minutes, so its line stays '
        '"New message"', () async {
      var now = DateTime(2026, 10, 11, 12);
      container.invalidate(messageNotificationProvider);
      withClock(
        Clock(() => now),
        () => container.read(messageNotificationProvider),
      );
      await deliver(locked());
      client.decryption.decrypted.add(textEvent(body: 'are you around?'));
      now = now.add(const Duration(minutes: 6));
      client.onSync.add(SyncUpdate(nextBatch: 's2'));
      await pumpEventQueue();

      await keyArrives();

      expect(client.decryption.attempts, 0);
      expect(linesOf(notifications.single), ['New message']);
      expect(notifications.cancelled, isEmpty);
    });

    group('on an iPhone, where the extension presents out of front', () {
      void inFront(bool front) =>
          TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
            front ? AppLifecycleState.resumed : AppLifecycleState.paused,
          );

      void stillShowing() => notifications.active = [
        {'id': messageNotificationIdFor(room.id), 'payload': ''},
      ];

      setUp(() {
        ambientCapabilities = iosCapabilities;
        notifications = installFakeLocalNotifications(
          platform: TargetPlatform.iOS,
        );
        installFakeCallsChannel();
        recordMethodChannel(
          'zuno/nse',
          reply: (call) => call.method == 'threadKey' ? 'tok' : null,
        );
        addTearDown(OpaqueThreadIds.instance.reset);
        addTearDown(() => inFront(true));
      });

      test('a line Zuno posted in front takes the message silently when the '
          'key arrives after Zuno left the front', () async {
        inFront(true);
        await deliver(locked());
        stillShowing();
        inFront(false);
        client.decryption.decrypted.add(textEvent(body: 'are you around?'));

        await keyArrives();

        expect(notifications.shown, hasLength(2));
        final refined = notifications.shown.last;
        expect(refined.id, messageNotificationIdFor(room.id));
        expect(refined.body, contains('are you around?'));
        expect(refined.android['presentAlert'], isFalse);
        expect(notifications.cancelled, isEmpty);
      });

      test('a message that turns out to need no notification still takes '
          'that line down', () async {
        inFront(true);
        await deliver(locked());
        stillShowing();
        inFront(false);
        client.decryption.decrypted.add(
          buildTestEvent(
            room,
            eventId: r'$1',
            senderId: '@a:x',
            content: {
              'msgtype': MessageTypes.Text,
              'body': '* fixed',
              'm.relates_to': {'rel_type': 'm.replace', 'event_id': r'$0'},
            },
          ),
        );

        await keyArrives();

        expect(notifications.shown, hasLength(1));
        expect(notifications.cancelled, [messageNotificationIdFor(room.id)]);
      });

      test('a line the user already cleared is not brought back', () async {
        inFront(true);
        await deliver(locked());
        inFront(false);
        client.decryption.decrypted.add(textEvent(body: 'are you around?'));

        await keyArrives();

        expect(notifications.shown, hasLength(1));
      });

      test('a message that arrived out of front is left to the extension when '
          'its key arrives', () async {
        inFront(false);
        await deliver(locked());
        client.decryption.decrypted.add(textEvent(body: 'are you around?'));

        await keyArrives();

        expect(notifications.shown, isEmpty);
      });
    });
  });

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
