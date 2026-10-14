import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/l10n/l10n.dart';
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

  void nameRoom(String name) {
    room.setState(
      Event(
        eventId: r'$name',
        type: EventTypes.RoomName,
        stateKey: '',
        senderId: '@me:example.org',
        originServerTs: DateTime.now(),
        content: {'name': name},
        room: room,
      ),
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
      expect(roomTitle(room, englishLocalizations), 'Bob');
    });

    test('a live direct chat is unchanged', () {
      markDirectWith('@bob:example.org');
      setMember('@bob:example.org', 'join', displayName: 'Bob');
      setCounts(joined: 2);

      expect(room.isAbandonedDMRoom, isFalse);
      expect(
        roomTitle(room, englishLocalizations),
        room.getLocalizedDisplayname(),
      );
    });

    test('a named room is unchanged', () {
      nameRoom('Team');
      setCounts(joined: 1);

      expect(roomTitle(room, englishLocalizations), 'Team');
    });

    test('an emptied unnamed group reads as an empty chat, not a dangling '
        'group', () {
      room.summary.mHeroes = ['@me:example.org'];
      setCounts(joined: 1);

      expect(roomTitle(room, englishLocalizations), 'Empty chat');
    });
  });

  group('loadRoomNameMembers', () {
    late StoredMembersFakeDatabaseApi db;

    setUp(() {
      db = StoredMembersFakeDatabaseApi();
      client = buildTestClient(userId: '@me:example.org', database: db);
      room = buildTestRoom(client)..membership = Membership.join;
      client.rooms.add(room);
    });

    test('names a direct chat after its partner as stored, not their '
        'username', () async {
      markDirectWith('@test2:example.org');
      db.displayNames['@test2:example.org'] = 'George';

      await loadRoomNameMembers(room);

      expect(roomTitle(room, englishLocalizations), 'George');
    });

    test('names an unnamed group after its stored members', () async {
      room.summary.mHeroes = ['@ann:example.org', '@ben:example.org'];
      db.displayNames.addAll({
        '@ann:example.org': 'Ann Lee',
        '@ben:example.org': 'Ben Ode',
      });

      await loadRoomNameMembers(room);

      expect(
        roomTitle(room, englishLocalizations),
        allOf(contains('Ann Lee'), contains('Ben Ode')),
      );
    });

    test('a chat with a name still loads its partner, but not its other '
        'members', () async {
      markDirectWith('@test2:example.org');
      nameRoom('Bridged');
      room.summary.mHeroes = ['@ann:example.org'];
      db.displayNames['@test2:example.org'] = 'George';

      await loadRoomNameMembers(room);

      expect(db.lookups, ['@test2:example.org']);
      expect(
        room
            .unsafeGetUserFromMemoryOrFallback('@test2:example.org')
            .calcDisplayname(),
        'George',
      );
    });

    test('looks nobody up for a room with a name', () async {
      nameRoom('Team');
      room.summary.mHeroes = ['@ann:example.org'];

      await loadRoomNameMembers(room);

      expect(db.lookups, isEmpty);
    });

    test('looks up neither me nor a member already loaded', () async {
      room.summary.mHeroes = ['@me:example.org', '@ann:example.org'];
      setMember('@ann:example.org', 'join', displayName: 'Ann Lee');

      await loadRoomNameMembers(room);

      expect(db.lookups, isEmpty);
    });

    test('a partner missing from storage keeps the fallback name', () async {
      markDirectWith('@test2:example.org');

      await loadRoomNameMembers(room);

      expect(db.lookups, ['@test2:example.org']);
      expect(roomTitle(room, englishLocalizations), isNot(contains('George')));
    });
  });

  group('partnerLeft', () {
    test('is set once the other person has left a direct chat', () {
      abandonedBy('@bob:example.org', displayName: 'Bob');

      final display = roomInviteDisplay(room, englishLocalizations);

      expect(display.partnerLeft, isTrue);
      expect(display.title, 'Bob');
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
