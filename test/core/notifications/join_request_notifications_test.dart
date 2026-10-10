import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/notifications/invite_notification_provider.dart';
import 'package:zuno/core/notifications/join_request_notification_provider.dart';

import '../../helpers/fake_local_notifications.dart';
import '../../helpers/fake_matrix.dart';
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
      originServerTs: DateTime.now(),
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
          originServerTs: DateTime.now(),
          content: {'membership': 'knock', 'displayname': 'Maya'},
          room: room,
        ),
      );
      await pumpEventQueue();

      final shown = notifications.shown.single;
      expect(shown.title, contains('Beginners'));
      expect(shown.body, 'Maya asks to join');
    });

    test('a new request tells those who can answer it', () {
      final content = joinRequestNotificationFor(client, knock());

      expect(content, isNotNull);
      expect(content!.roomId, room.id);
      expect(content.title, 'Beginners');
      expect(content.body, 'Ines asks to join');
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

      expect(content.body, '@ines asks to join');
      expect(content.senderAvatarUrl, Uri.parse('mxc://x/ines'));
    });

    test('a very long name is shortened', () {
      final long = knock(
        eventId: r'$long',
        content: {'membership': 'knock', 'displayname': 'I' * 200},
      );

      final body = joinRequestNotificationFor(client, long)!.body;

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
