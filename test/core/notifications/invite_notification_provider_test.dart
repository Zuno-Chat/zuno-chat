import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/notifications/invite_notification_provider.dart';

import '../../helpers/fake_local_notifications.dart';
import '../../helpers/fake_matrix.dart';
import '../../helpers/preferences_container.dart';

void main() {
  late Client client;
  late Room room;

  setUp(() {
    client = buildTestClient(userId: '@me:example.org');
    room = buildTestRoom(client);
    room.membership = Membership.invite;
    room.setState(
      User(
        '@alice:example.org',
        displayName: 'Alice',
        membership: 'join',
        room: room,
      ),
    );
  });

  Event inviteEvent({
    String stateKey = '@me:example.org',
    String membership = 'invite',
    String senderId = '@alice:example.org',
    String type = EventTypes.RoomMember,
  }) {
    return Event(
      eventId: r'$invite',
      type: type,
      stateKey: stateKey,
      senderId: senderId,
      originServerTs: DateTime.now(),
      content: {'membership': membership},
      room: room,
    );
  }

  test('notifies for an invitation addressed to this user', () {
    final content = inviteNotificationFor(client, inviteEvent());

    expect(content, isNotNull);
    expect(content!.roomId, room.id);
    expect(content.title, 'Alice');
    expect(content.body, 'Invited you to chat');
    expect(content.isDirectChat, isFalse);
    expect(content.eventId, r'$invite');
  });

  test('names the group when the room has a name of its own', () {
    room.setState(
      Event(
        eventId: r'$name',
        type: EventTypes.RoomName,
        stateKey: '',
        senderId: '@alice:example.org',
        originServerTs: DateTime.now(),
        content: {'name': 'Weekend plans'},
        room: room,
      ),
    );

    expect(
      inviteNotificationFor(client, inviteEvent())?.body,
      'Invited you to Weekend plans',
    );
  });

  for (final (name, event) in <(String, Event Function())>[
    (
      'ignores an invitation addressed to someone else',
      () => inviteEvent(stateKey: '@bob:example.org'),
    ),
    (
      'ignores a membership change that is not an invitation',
      () => inviteEvent(membership: 'join'),
    ),
    (
      'ignores an ordinary message event',
      () => inviteEvent(type: EventTypes.Message),
    ),
    (
      'ignores an invitation this user somehow sent themselves',
      () => inviteEvent(senderId: '@me:example.org'),
    ),
  ]) {
    test(name, () {
      expect(inviteNotificationFor(client, event()), isNull);
    });
  }

  test('the sync path\'s stand-in event id is no event id at all', () {
    final event = Event(
      eventId: 'invite_for_${room.id}',
      type: EventTypes.RoomMember,
      stateKey: '@me:example.org',
      senderId: '@alice:example.org',
      originServerTs: DateTime.now(),
      content: {'membership': 'invite'},
      room: room,
    );

    expect(inviteNotificationFor(client, event)?.eventId, isNull);
  });

  group('announced once, whichever path is first', () {
    late RecordedNotifications notifications;

    setUp(() async {
      notifications = installFakeLocalNotifications();
      installSilentNotificationSideChannels();
      client.rooms.add(room);
      final container = await containerWithPreferences(
        {},
        overrides: [matrixClientProvider.overrideWithValue(client)],
      );
      container.read(roomInviteNotificationProvider);
    });

    Event fromSync() => Event(
      eventId: 'invite_for_${room.id}',
      type: EventTypes.RoomMember,
      stateKey: '@me:example.org',
      senderId: '@alice:example.org',
      originServerTs: DateTime.now(),
      content: {'membership': 'invite'},
      room: room,
    );

    Future<void> sync(SyncUpdate update) async {
      client.onSync.add(update);
      await pumpEventQueue();
    }

    Future<void> deliver() async {
      client.onNotification.add(fromSync());
      await pumpEventQueue();
    }

    test('an invitation the push already announced is not announced again '
        'from sync', () async {
      expect((await claimInviteAnnouncement(room.id)).won, isTrue);

      await deliver();

      expect(notifications.shown, isEmpty);
    });

    test('an invitation sync repeats is announced once', () async {
      await deliver();
      await deliver();

      expect(notifications.shown, hasLength(1));
      expect((await claimInviteAnnouncement(room.id)).won, isFalse);
    });

    test('once the invitation is settled, a new one to the same room is '
        'announced again', () async {
      await deliver();
      await sync(
        SyncUpdate(
          nextBatch: 's2',
          rooms: RoomsUpdate(join: {room.id: JoinedRoomUpdate()}),
        ),
      );

      await deliver();

      expect(notifications.shown, hasLength(2));
    });

    test('a declined invitation is settled too', () async {
      await deliver();
      await sync(
        SyncUpdate(
          nextBatch: 's2',
          rooms: RoomsUpdate(leave: {room.id: LeftRoomUpdate()}),
        ),
      );

      expect((await claimInviteAnnouncement(room.id)).won, isTrue);
    });

    test('joining from another device settles an invitation another path '
        'announced', () async {
      await claimInviteAnnouncement(room.id);
      await sync(
        SyncUpdate(
          nextBatch: 's2',
          rooms: RoomsUpdate(
            join: {
              room.id: JoinedRoomUpdate(
                timeline: TimelineUpdate(
                  events: [
                    MatrixEvent(
                      type: EventTypes.RoomMember,
                      stateKey: '@me:example.org',
                      senderId: '@me:example.org',
                      eventId: r'$join',
                      originServerTs: DateTime.now(),
                      content: {'membership': 'join'},
                    ),
                  ],
                ),
              ),
            },
          ),
        ),
      );

      expect((await claimInviteAnnouncement(room.id)).won, isTrue);
    });

    test('a sync about other rooms settles nothing', () async {
      await deliver();
      await sync(
        SyncUpdate(
          nextBatch: 's2',
          rooms: RoomsUpdate(join: {'!other:example.org': JoinedRoomUpdate()}),
        ),
      );

      await deliver();

      expect(notifications.shown, hasLength(1));
    });
  });
}
