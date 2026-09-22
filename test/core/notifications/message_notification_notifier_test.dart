import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/notifications/message_notification_provider.dart';
import 'package:zuno/core/notifications/notified_events_store.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

import '../../helpers/fake_local_notifications.dart';
import '../../helpers/fake_matrix.dart';

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

    test('takes the room notification down once a sync says nothing is '
        'unread there', () async {
      await deliver(textEvent(body: 'hi'));
      notifications.active = [
        {
          'id': roomNotificationId,
          'channelId': 'direct_messages',
          'payload': '',
        },
      ];

      await syncWithCount(0);

      expect(notifications.cancelled, contains(roomNotificationId));
    });

    test('leaves the room alone while it still has unread messages', () async {
      await deliver(textEvent(body: 'hi'));
      notifications.active = [
        {
          'id': roomNotificationId,
          'channelId': 'direct_messages',
          'payload': '',
        },
      ];

      await syncWithCount(2);

      expect(notifications.cancelled, isEmpty);
    });

    test('does nothing for a room with no notification showing', () async {
      notifications.active = const [];

      await syncWithCount(0);

      expect(notifications.cancelled, isEmpty);
    });
  });
}
