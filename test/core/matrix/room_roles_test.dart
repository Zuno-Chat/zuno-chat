import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/communities.dart';
import 'package:zuno/core/matrix/room_permission.dart';
import 'package:zuno/core/matrix/room_roles.dart';

import '../../helpers/fake_matrix.dart';

class _StoredMembers extends FakeDatabaseApi {
  final users = <String, String>{};

  @override
  Future<User?> getUser(String userId, Room room) async {
    final membership = users[userId];
    return membership == null
        ? null
        : User(userId, membership: membership, room: room);
  }
}

void main() {
  void setPowerLevels(Room room, Map<String, Object?> content) {
    room.setState(
      buildTestEvent(
        room,
        eventId: r'$powerlevels',
        senderId: '@creator:example.org',
        type: EventTypes.RoomPowerLevels,
        stateKey: '',
        content: content,
      ),
    );
  }

  Room roomAs(String me, Map<String, int> users) {
    final room = buildTestRoom(buildTestClient(userId: me));
    setPowerLevels(room, {'users': users});
    return room;
  }

  group('roomRoleForLevel', () {
    test('classifies each boundary', () {
      expect(roomRoleForLevel(-1), RoomRole.readOnly);
      expect(roomRoleForLevel(-100), RoomRole.readOnly);
      expect(roomRoleForLevel(0), RoomRole.member);
      expect(roomRoleForLevel(49), RoomRole.member);
      expect(roomRoleForLevel(50), RoomRole.moderator);
      expect(roomRoleForLevel(99), RoomRole.moderator);
      expect(roomRoleForLevel(100), RoomRole.admin);
      expect(roomRoleForLevel(9001), RoomRole.admin);
    });
  });

  group('assignableRolesFor', () {
    test('an admin can assign any role to a lower-level member', () {
      final room = roomAs('@admin:example.org', {
        '@admin:example.org': 100,
        '@bob:example.org': 0,
      });
      expect(
        assignableRolesFor(room, targetUserId: '@bob:example.org'),
        containsAll(RoomRole.values),
      );
    });

    test(
      'a moderator can only offer member or read-only, never moderator/admin',
      () {
        final room = roomAs('@mod:example.org', {
          '@mod:example.org': 50,
          '@bob:example.org': 0,
        });
        expect(
          assignableRolesFor(room, targetUserId: '@bob:example.org'),
          unorderedEquals([RoomRole.readOnly, RoomRole.member]),
        );
      },
    );

    test('a moderator cannot assign roles where only admins change them', () {
      for (final levels in [defaultGroupPowerLevels(), communityPowerLevels]) {
        final room = buildTestRoom(buildTestClient(userId: '@mod:example.org'));
        setPowerLevels(room, {
          ...levels,
          'users': {'@mod:example.org': 50, '@bob:example.org': 0},
        });
        expect(
          assignableRolesFor(room, targetUserId: '@bob:example.org'),
          isEmpty,
        );
      }
    });

    test('an admin keeps every role under the default power levels', () {
      final room = buildTestRoom(buildTestClient(userId: '@admin:example.org'));
      setPowerLevels(room, {
        ...defaultGroupPowerLevels(),
        'users': {'@admin:example.org': 100, '@bob:example.org': 0},
      });
      expect(
        assignableRolesFor(room, targetUserId: '@bob:example.org'),
        containsAll(RoomRole.values),
      );
    });

    test('a member or read-only user cannot assign any role', () {
      final room = roomAs('@member:example.org', {
        '@member:example.org': 0,
        '@ro:example.org': -1,
      });
      expect(
        assignableRolesFor(room, targetUserId: '@ro:example.org'),
        isEmpty,
      );
    });

    test('nobody can assign themselves a role through this', () {
      final room = roomAs('@admin:example.org', {'@admin:example.org': 100});
      expect(
        assignableRolesFor(room, targetUserId: '@admin:example.org'),
        isEmpty,
      );
    });
  });

  group('isLastAdmin', () {
    late _StoredMembers stored;

    Room adminRoom({
      Map<String, int> users = const {},
      int joined = 5,
      String me = '@admin:example.org',
    }) {
      stored = _StoredMembers();
      final room = buildTestRoom(buildTestClient(userId: me, database: stored));
      setPowerLevels(room, {
        ...defaultGroupPowerLevels(),
        'users': {'@admin:example.org': 100, '@bob:example.org': 0, ...users},
      });
      room.summary.mJoinedMemberCount = joined;
      return room;
    }

    void setMembership(Room room, String userId, String membership) =>
        room.setState(User(userId, membership: membership, room: room));

    test('the only admin among other members is the last one', () async {
      expect(await isLastAdmin(adminRoom()), isTrue);
    });

    test('an admin who left, here or only on record, does not count', () async {
      final room = adminRoom(
        users: {'@gone:example.org': 100, '@banned:example.org': 100},
      );
      setMembership(room, '@gone:example.org', 'leave');
      stored.users['@banned:example.org'] = 'ban';

      expect(await isLastAdmin(room), isTrue);
    });

    test('another admin who is still here or invited does', () async {
      final joined = adminRoom(users: {'@carol:example.org': 100});
      setMembership(joined, '@carol:example.org', 'join');
      expect(await isLastAdmin(joined), isFalse);

      final invited = adminRoom(users: {'@carol:example.org': 100});
      stored.users['@carol:example.org'] = 'invite';
      expect(await isLastAdmin(invited), isFalse);
    });

    test('an admin whose membership is unknown is taken to be here', () async {
      expect(
        await isLastAdmin(adminRoom(users: {'@carol:example.org': 100})),
        isFalse,
      );
    });

    test(
      'nobody else left, or not being an admin, is never the last admin',
      () async {
        expect(await isLastAdmin(adminRoom(joined: 1)), isFalse);
        expect(await isLastAdmin(adminRoom(me: '@bob:example.org')), isFalse);
      },
    );
  });

  group('canManageMember', () {
    test('a lower-level target is manageable', () {
      final room = roomAs('@admin:example.org', {
        '@admin:example.org': 100,
        '@bob:example.org': 0,
      });
      expect(canManageMember(room, '@bob:example.org'), isTrue);
    });

    test('a peer or superior target is not manageable', () {
      final room = roomAs('@mod:example.org', {
        '@mod:example.org': 50,
        '@othermod:example.org': 50,
        '@admin:example.org': 100,
      });
      expect(canManageMember(room, '@othermod:example.org'), isFalse);
      expect(canManageMember(room, '@admin:example.org'), isFalse);
    });

    test('you can never manage yourself', () {
      final room = roomAs('@admin:example.org', {'@admin:example.org': 100});
      expect(canManageMember(room, '@admin:example.org'), isFalse);
    });
  });

  group('bannedUserIds', () {
    void setMember(Room room, String userId, String membership) {
      room.setState(
        buildTestEvent(
          room,
          eventId: '\$member-$userId',
          senderId: '@admin:example.org',
          type: EventTypes.RoomMember,
          stateKey: userId,
          content: {'membership': membership},
        ),
      );
    }

    test('lists only banned members, not joined/invited ones', () {
      final client = buildTestClient(userId: '@admin:example.org');
      final room = buildTestRoom(client);
      setMember(room, '@alice:example.org', 'join');
      setMember(room, '@bob:example.org', 'ban');
      setMember(room, '@carol:example.org', 'invite');
      setMember(room, '@dave:example.org', 'ban');

      expect(
        bannedUserIds(room),
        unorderedEquals(['@bob:example.org', '@dave:example.org']),
      );
    });

    test('an empty room has no banned users', () {
      final client = buildTestClient(userId: '@admin:example.org');
      final room = buildTestRoom(client);
      expect(bannedUserIds(room), isEmpty);
    });
  });

  void setCreator(Room room, String userId) {
    room.setState(
      buildTestEvent(
        room,
        eventId: r'$create',
        senderId: userId,
        type: EventTypes.RoomCreate,
        stateKey: '',
        content: {'creator': userId, 'room_version': '10'},
      ),
    );
  }

  Room roomSeenBy(String viewer, {required int level}) {
    final room = buildTestRoom(buildTestClient(userId: viewer));
    setCreator(room, '@owner:example.org');
    setPowerLevels(room, {
      'users': {'@owner:example.org': 100, viewer: level},
    });
    return room;
  }

  group('owners', () {
    test('isRoomOwner reads the create event sender', () {
      final room = roomSeenBy('@me:example.org', level: 0);

      expect(isRoomOwner(room, '@owner:example.org'), isTrue);
      expect(isRoomOwner(room, '@me:example.org'), isFalse);
    });

    test('membersOwnerFirst puts owners ahead and keeps the rest in order', () {
      final room = roomSeenBy('@me:example.org', level: 0);
      final users = [
        User('@bob:example.org', membership: 'join', room: room),
        User('@owner:example.org', membership: 'join', room: room),
        User('@alice:example.org', membership: 'join', room: room),
      ];

      expect(membersOwnerFirst(room, users).map((u) => u.id), [
        '@owner:example.org',
        '@bob:example.org',
        '@alice:example.org',
      ]);
    });

    test('canSeeAdvancedRoomInfo: owners and admins, not moderators', () {
      expect(
        canSeeAdvancedRoomInfo(roomSeenBy('@owner:example.org', level: 100)),
        isTrue,
      );
      expect(
        canSeeAdvancedRoomInfo(roomSeenBy('@me:example.org', level: 100)),
        isTrue,
      );
      expect(
        canSeeAdvancedRoomInfo(roomSeenBy('@me:example.org', level: 50)),
        isFalse,
      );
      expect(
        canSeeAdvancedRoomInfo(roomSeenBy('@me:example.org', level: 0)),
        isFalse,
      );
    });
  });

  group('memberBadge', () {
    User member(Room room, String id, {String membership = 'join'}) =>
        User(id, membership: membership, room: room);

    test('a moderator sees every role, with the owner as Owner', () {
      final room = roomSeenBy('@me:example.org', level: 50);
      setPowerLevels(room, {
        'users': {
          '@owner:example.org': 100,
          '@me:example.org': 50,
          '@admin:example.org': 100,
        },
      });

      expect(memberBadge(room, member(room, '@owner:example.org')), 'Owner');
      expect(memberBadge(room, member(room, '@admin:example.org')), 'Admin');
      expect(memberBadge(room, member(room, '@me:example.org')), 'Moderator');
      expect(memberBadge(room, member(room, '@bob:example.org')), 'Member');
    });

    test('a member sees only Owner and Invited', () {
      final room = roomSeenBy('@me:example.org', level: 0);
      setPowerLevels(room, {
        'users': {'@owner:example.org': 100, '@admin:example.org': 100},
      });

      expect(memberBadge(room, member(room, '@owner:example.org')), 'Owner');
      expect(memberBadge(room, member(room, '@admin:example.org')), isNull);
      expect(memberBadge(room, member(room, '@bob:example.org')), isNull);
      expect(
        memberBadge(
          room,
          member(room, '@new:example.org', membership: 'invite'),
        ),
        'Invited',
      );
    });
  });

  group('setUserRoomRole', () {
    late List<http.Request> requests;
    late http.Response Function() server;
    late Room room;

    setUp(() {
      requests = [];
      server = () => http.Response(jsonEncode({'event_id': r'$pl2'}), 200);
      final client = buildTestClient(
        userId: '@me:example.org',
        httpClient: MockClient((request) async {
          requests.add(request);
          return server();
        }),
      );
      client.baseUri = Uri.parse('https://example.org');
      client.bearerToken = 'token';
      room = buildTestRoom(client);
      setPowerLevels(room, {
        'ban': 50,
        'users': {'@me:example.org': 100},
      });
    });

    test('sends the power levels with only that user changed', () async {
      await setUserRoomRole(room, '@bob:example.org', RoomRole.moderator);

      final request = requests.single;
      expect(request.method, 'PUT');
      expect(request.url.path, contains('/state/m.room.power_levels'));
      expect(jsonDecode(request.body), {
        'ban': 50,
        'users': {'@me:example.org': 100, '@bob:example.org': 50},
      });
    });

    test('shows the new role before the server echoes it back', () async {
      await setUserRoomRole(room, '@bob:example.org', RoomRole.readOnly);

      expect(roomRoleOfUser(room, '@bob:example.org'), RoomRole.readOnly);
    });

    test('a room without power levels gets a users map', () async {
      room.states.remove(EventTypes.RoomPowerLevels);

      await setUserRoomRole(room, '@bob:example.org', RoomRole.admin);

      expect(jsonDecode(requests.single.body), {
        'users': {'@bob:example.org': 100},
      });
    });

    test('a refused change leaves the role as it was', () async {
      server = () => http.Response(
        jsonEncode({'errcode': 'M_FORBIDDEN', 'error': 'no'}),
        403,
      );

      await expectLater(
        setUserRoomRole(room, '@bob:example.org', RoomRole.admin),
        throwsA(isA<MatrixException>()),
      );
      expect(roomRoleOfUser(room, '@bob:example.org'), RoomRole.member);
    });
  });
}
