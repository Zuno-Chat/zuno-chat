import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/room_invite.dart';
import 'package:zuno/core/matrix/room_permission.dart';
import 'package:zuno/core/matrix/room_title.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  late Client client;
  late Room room;

  setUp(() {
    client = buildTestClient(userId: '@me:example.org');
    room = buildTestRoom(client);
    room.membership = Membership.join;
  });

  void setMember(String userId, String membership, {String? displayName}) {
    room.setState(
      Event(
        eventId: '\$member-$userId-$membership',
        type: EventTypes.RoomMember,
        stateKey: userId,
        senderId: userId,
        originServerTs: DateTime.now(),
        content: {'membership': membership, 'displayname': ?displayName},
        room: room,
      ),
    );
  }

  void markDirectWith(String userId) {
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        userId: [room.id],
      },
    );
  }

  void setCounts({required int joined, int invited = 0}) {
    room.summary.mJoinedMemberCount = joined;
    room.summary.mInvitedMemberCount = invited;
  }

  void abandonedBy(String userId, {String? displayName}) {
    markDirectWith(userId);
    setMember(userId, 'leave', displayName: displayName);
    setCounts(joined: 1);
  }

  group('roomTitle', () {
    test('an abandoned direct chat keeps the name of who left', () {
      abandonedBy('@bob:example.org', displayName: 'Bob');

      expect(room.isAbandonedDMRoom, isTrue);
      expect(roomTitle(room), 'Bob');
    });

    test('an abandoned direct chat falls back to the localpart', () {
      abandonedBy('@bob:example.org');

      expect(roomTitle(room), 'Bob');
    });

    test('a live direct chat is unchanged', () {
      markDirectWith('@bob:example.org');
      setMember('@bob:example.org', 'join', displayName: 'Bob');
      setCounts(joined: 2);

      expect(room.isAbandonedDMRoom, isFalse);
      expect(roomTitle(room), room.getLocalizedDisplayname());
    });

    test('a named room is unchanged', () {
      room.setState(
        Event(
          eventId: r'$name',
          type: EventTypes.RoomName,
          stateKey: '',
          senderId: '@me:example.org',
          originServerTs: DateTime.now(),
          content: {'name': 'Team'},
          room: room,
        ),
      );
      setCounts(joined: 1);

      expect(roomTitle(room), 'Team');
    });

    test('an emptied unnamed group does not read as a dangling group', () {
      room.summary.mHeroes = ['@me:example.org'];
      setCounts(joined: 1);

      expect(roomTitle(room), isNot(startsWith('Group with')));
      expect(roomTitle(room).trim(), isNotEmpty);
    });
  });

  group('partnerLeft', () {
    test('is set once the other person has left a direct chat', () {
      abandonedBy('@bob:example.org', displayName: 'Bob');

      final display = roomInviteDisplay(room);

      expect(display.partnerLeft, isTrue);
      expect(display.title, 'Bob');
    });

    test('is not set while they are still here', () {
      markDirectWith('@bob:example.org');
      setMember('@bob:example.org', 'join', displayName: 'Bob');
      setCounts(joined: 2);

      expect(roomInviteDisplay(room).partnerLeft, isFalse);
    });

    test('is not set for a group room', () {
      setCounts(joined: 1);

      expect(roomInviteDisplay(room).partnerLeft, isFalse);
    });
  });

  group('canPostInRoom', () {
    test('is false once the other person has left', () {
      abandonedBy('@bob:example.org', displayName: 'Bob');

      expect(room.canSendDefaultMessages, isTrue);
      expect(canPostInRoom(room), isFalse);
    });

    test('is true in a live direct chat', () {
      markDirectWith('@bob:example.org');
      setMember('@bob:example.org', 'join', displayName: 'Bob');
      setCounts(joined: 2);

      expect(canPostInRoom(room), isTrue);
    });
  });
}
