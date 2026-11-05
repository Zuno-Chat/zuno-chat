import 'package:clock/clock.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/client/matrix_client_provider.dart';
import 'package:zuno/core/notifications/join_request_notification_provider.dart';
import 'package:zuno/core/notifications/messages/message_notification_provider.dart';
import 'package:zuno/core/notifications/messages/notification_ids.dart';
import 'package:zuno/core/notifications/messages/notification_thread_store.dart';
import 'package:zuno/core/notifications/room_invite_notification_provider.dart';
import 'package:zuno/core/notifications/settings/notification_preview.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../helpers/fake_local_notifications.dart';
import '../../helpers/fake_matrix.dart';
import '../../helpers/native_method_calls.dart';
import '../../helpers/platform_capabilities.dart';
import '../../helpers/preferences_container.dart';

const _me = '@me:example.org';

void main() {
  late Client client;
  late RecordedNotifications notifications;

  Future<ProviderContainer> container({List<String> asked = const []}) =>
      containerWithPreferences(
        {'communities.asked.$_me': asked},
        overrides: [matrixClientProvider.overrideWithValue(client)],
      );

  setUp(() {
    notifications = installFakeLocalNotifications();
    installSilentNotificationSideChannels();
    client = buildTestClient(userId: _me);
  });

  Room named(String id, String name, Membership membership) {
    final room = buildTestRoom(client, id: id)..membership = membership;
    room.setState(
      Event(
        eventId: '\$name-$id',
        type: EventTypes.RoomName,
        stateKey: '',
        senderId: '@admin:example.org',
        originServerTs: DateTime(2026),
        content: {'name': name},
        room: room,
      ),
    );
    client.rooms.add(room);
    return room;
  }

  group('invitations', () {
    Event invite(Room room) => Event(
      eventId: '\$invite-${room.id}',
      type: EventTypes.RoomMember,
      stateKey: _me,
      senderId: '@admin:example.org',
      originServerTs: clock.now(),
      content: {'membership': 'invite'},
      room: room,
    );

    test('an approval of a request stays quiet, since Zuno joins it', () async {
      final coaches = named('!coaches:x', 'Coaches', Membership.invite);
      final c = await container(asked: [coaches.id]);
      c.read(roomInviteNotificationProvider);

      client.onNotification.add(invite(coaches));
      await pumpEventQueue();

      expect(notifications.shown, isEmpty);
    });

    group('on an iPhone', () {
      setUp(() {
        ambientCapabilities = iosCapabilities;
        notifications = installFakeLocalNotifications(
          platform: TargetPlatform.iOS,
        );
        TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      });

      test(
        'an invitation the extension already showed is not shown again',
        () async {
          final asked = recordMethodChannel(
            'zuno/nse',
            reply: (call) => call.method == 'shownByExtension' ? [true] : null,
          );
          final trips = named('!trips:x', 'Trips', Membership.invite);
          final c = await container();
          c.read(roomInviteNotificationProvider);

          client.onNotification.add(invite(trips));
          await pumpEventQueue();

          expect(notifications.shown, isEmpty);
          expect(asked.argsOf('shownByExtension'), [
            {
              'claims': [
                {'kind': 'invite', 'id': trips.id},
              ],
            },
          ]);
        },
      );

      test('an invitation whose alert Zuno hid in front is shown once that is '
          'known', () async {
        var claimed = true;
        recordMethodChannel(
          'zuno/nse',
          reply: (call) => call.method == 'shownByExtension' ? [claimed] : null,
        );
        final trips = named('!trips:x', 'Trips', Membership.invite);
        final c = await container();
        c.read(roomInviteNotificationProvider);
        client.onNotification.add(invite(trips));
        await pumpEventQueue();
        expect(notifications.shown, isEmpty);

        claimed = false;
        await callFromNative(
          const MethodChannel('zuno/nse'),
          'alertHiddenInFront',
        );
        await pumpEventQueue();

        expect(notifications.shown.single.body, 'Invited you to Trips');
      });
    });

    test('any other invitation still notifies', () async {
      final trips = named('!trips:x', 'Trips', Membership.invite);
      final c = await container();
      c.read(roomInviteNotificationProvider);

      client.onNotification.add(invite(trips));
      await pumpEventQueue();

      expect(notifications.shown.single.body, 'Invited you to Trips');
    });
  });

  group('requests to join', () {
    late Room room;

    void levels(int mine) => room.setState(
      Event(
        eventId: r'$levels',
        type: EventTypes.RoomPowerLevels,
        stateKey: '',
        senderId: '@admin:example.org',
        originServerTs: DateTime(2026),
        content: {
          'users': {_me: mine},
          'invite': 0,
          'kick': 50,
        },
        room: room,
      ),
    );

    Event knock({
      String eventId = r'$knock',
      Map<String, Object?> content = const {
        'membership': 'knock',
        'displayname': 'Ines',
      },
    }) => Event(
      eventId: eventId,
      type: EventTypes.RoomMember,
      stateKey: '@ines:example.org',
      senderId: '@ines:example.org',
      originServerTs: DateTime(2026, 9, 29),
      content: content,
      room: room,
    );

    setUp(() {
      room = named('!beginners:x', 'Beginners', Membership.join);
      levels(50);
    });

    test('a new request is shown to someone who can answer it', () async {
      final c = await container();
      c.read(joinRequestNotificationProvider);

      client.onTimelineEvent.add(
        Event(
          eventId: r'$knock',
          type: EventTypes.RoomMember,
          stateKey: '@maya:x',
          senderId: '@maya:x',
          originServerTs: clock.now(),
          content: {'membership': 'knock', 'displayname': 'Maya'},
          room: room,
        ),
      );
      await pumpEventQueue();

      final shown = notifications.shown.single;
      expect(shown.title, contains('Beginners'));
      expect(shown.body, 'Maya asks to join');
    });

    test('at Nothing a request names neither the room nor who asks', () async {
      final c = await containerWithPreferences(
        {notificationPreviewKey: NotificationPreview.nothing.name},
        overrides: [matrixClientProvider.overrideWithValue(client)],
      );
      c.read(joinRequestNotificationProvider);

      client.onTimelineEvent.add(knock());
      await pumpEventQueue();

      final shown = notifications.shown.single;
      expect(shown.title, 'Zuno');
      expect(shown.body, 'New message');
      expect(shown.android['largeIcon'], isNull);
      expect(shown.android['shortcutId'], isNull);
    });

    test(
      'at Name only a request keeps its line, which holds no message',
      () async {
        final c = await containerWithPreferences(
          {notificationPreviewKey: NotificationPreview.nameOnly.name},
          overrides: [matrixClientProvider.overrideWithValue(client)],
        );
        c.read(joinRequestNotificationProvider);

        client.onTimelineEvent.add(knock());
        await pumpEventQueue();

        expect(notifications.shown.single.body, 'Ines asks to join');
      },
    );

    group('on screen', () {
      final maya = joinRequestThread('!beginners:x', '@maya:x');
      final mayasId = messageNotificationIdFor(maya);
      final roomsId = messageNotificationIdFor('!beginners:x');

      Event member(String userId, String membership, {String? eventId}) =>
          Event(
            eventId: eventId ?? '\$$membership-$userId',
            type: EventTypes.RoomMember,
            stateKey: userId,
            senderId: membership == 'knock' ? userId : _me,
            originServerTs: clock.now(),
            content: {'membership': membership, 'displayname': 'Maya'},
            room: room,
          );

      Future<void> sync({
        List<Event> timeline = const [],
        List<Event> state = const [],
        int? unread,
      }) async {
        client.onSync.add(
          SyncUpdate(
            nextBatch: 's2',
            rooms: RoomsUpdate(
              join: {
                room.id: JoinedRoomUpdate(
                  state: [
                    for (final e in state) MatrixEvent.fromJson(e.toJson()),
                  ],
                  timeline: TimelineUpdate(
                    events: [
                      for (final e in timeline)
                        MatrixEvent.fromJson(e.toJson()),
                    ],
                  ),
                  unreadNotifications: unread == null
                      ? null
                      : UnreadNotificationCounts(notificationCount: unread),
                ),
              },
            ),
          ),
        );
        await pumpEventQueue();
      }

      Future<void> knockFromMaya() async {
        final c = await container();
        c.read(joinRequestNotificationProvider);
        c.read(messageNotificationProvider);
        client.onTimelineEvent.add(member('@maya:x', 'knock'));
        await pumpEventQueue();
        notifications.active = [
          {'id': mayasId, 'channelId': 'group_messages', 'payload': ''},
          {'id': roomsId, 'channelId': 'group_messages', 'payload': ''},
        ];
      }

      test('a request has a notification of its own, apart from the room\'s '
          'messages', () async {
        await knockFromMaya();

        expect(notifications.shown.single.id, mayasId);
        expect(notifications.shown.single.payload, contains('!beginners:x'));
      });

      test('stays when the room\'s messages are read elsewhere', () async {
        await knockFromMaya();

        await sync(unread: 0);

        expect(notifications.cancelled, contains(roomsId));
        expect(notifications.cancelled, isNot(contains(mayasId)));
      });

      test('comes down once the request is answered', () async {
        await knockFromMaya();

        await sync(timeline: [member('@maya:x', 'invite')]);

        expect(notifications.cancelled, [mayasId]);
      });

      test('comes down once the requester gives up, even when only the '
          'room state says so', () async {
        await knockFromMaya();

        await sync(state: [member('@maya:x', 'leave')]);

        expect(notifications.cancelled, [mayasId]);
      });

      test('a request answered in the sync that brought it comes down after '
          'its post lands, never before', () async {
        final c = await container();
        c.read(joinRequestNotificationProvider);
        notifications.active = [
          {'id': mayasId, 'channelId': 'group_messages', 'payload': ''},
        ];

        client.onTimelineEvent.add(member('@maya:x', 'knock'));
        await sync(timeline: [member('@maya:x', 'invite')]);

        final methods = notifications.methods;
        expect(notifications.cancelled, [mayasId]);
        expect(
          methods.lastIndexOf('cancel'),
          greaterThan(methods.lastIndexOf('show')),
        );
      });

      test('stays while the requester still waits, and for someone else\'s '
          'change', () async {
        await knockFromMaya();

        await sync(
          timeline: [
            member('@maya:x', 'leave', eventId: r'$gave-up'),
            member('@maya:x', 'knock', eventId: r'$again'),
            member('@sam:x', 'join'),
          ],
        );

        expect(notifications.cancelled, isEmpty);
      });
    });

    test('a new request tells those who can answer it', () {
      final content = joinRequestNotificationFor(client, knock());

      expect(content, isNotNull);
      expect(content!.roomId, room.id);
      expect(content.title, 'Beginners');
      expect(content.text, 'Ines asks to join');
      expect(content.kind, NotificationLineKind.notice);
      expect(content.isDirectChat, isFalse);
    });

    test('those who cannot answer are not told', () {
      levels(0);

      expect(joinRequestNotificationFor(client, knock()), isNull);
    });

    test('a request already answered is not announced', () {
      room.setState(
        User('@ines:example.org', membership: 'invite', room: room),
      );

      expect(joinRequestNotificationFor(client, knock()), isNull);
    });

    test('without a name it uses the username, and carries the photo', () {
      final plain = knock(
        eventId: r'$plain',
        content: {'membership': 'knock', 'avatar_url': 'mxc://x/ines'},
      );

      final content = joinRequestNotificationFor(client, plain)!;

      expect(content.text, '@ines asks to join');
      expect(content.senderAvatarUrl, Uri.parse('mxc://x/ines'));
    });

    test('a very long name is shortened', () {
      final long = knock(
        eventId: r'$long',
        content: {'membership': 'knock', 'displayname': 'I' * 200},
      );

      final body = joinRequestNotificationFor(client, long)!.text;

      expect(body.length, lessThan(60));
      expect(body, endsWith('… asks to join'));
    });

    test('a request to join a community is not announced', () {
      room.setState(
        Event(
          eventId: r'$create',
          type: EventTypes.RoomCreate,
          stateKey: '',
          senderId: _me,
          originServerTs: DateTime(2026),
          content: {'type': 'm.space'},
          room: room,
        ),
      );

      expect(joinRequestNotificationFor(client, knock()), isNull);
    });

    test('other membership changes are not requests', () {
      final join = knock(eventId: r'$join', content: {'membership': 'join'});

      expect(joinRequestNotificationFor(client, join), isNull);
    });
  });
}
