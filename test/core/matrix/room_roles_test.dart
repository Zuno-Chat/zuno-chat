import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/room_roles.dart';

import '../../helpers/fake_matrix.dart';

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

  group('ownRoomRole / roomRoleOfUser', () {
    test('reads the room creator as admin by default', () {
      final client = buildTestClient(userId: '@creator:example.org');
      final room = buildTestRoom(client);
      room.setState(
        buildTestEvent(
          room,
          eventId: r'$create',
          senderId: '@creator:example.org',
          type: EventTypes.RoomCreate,
          stateKey: '',
        ),
      );
      expect(ownRoomRole(room), RoomRole.admin);
    });

    test('reads an explicit users entry for another member', () {
      final client = buildTestClient(userId: '@alice:example.org');
      final room = buildTestRoom(client);
      setPowerLevels(room, {
        'users': {'@bob:example.org': 50},
      });
      expect(roomRoleOfUser(room, '@bob:example.org'), RoomRole.moderator);
      expect(roomRoleOfUser(room, '@carol:example.org'), RoomRole.member);
    });
  });

  group('assignableRolesFor', () {
    test('an admin can assign any role to a lower-level member', () {
      final client = buildTestClient(userId: '@admin:example.org');
      final room = buildTestRoom(client);
      setPowerLevels(room, {
        'users': {'@admin:example.org': 100, '@bob:example.org': 0},
      });
      expect(
        assignableRolesFor(room, targetUserId: '@bob:example.org'),
        containsAll(RoomRole.values),
      );
    });

    test(
      'a moderator can only offer member or read-only, never moderator/admin',
      () {
        final client = buildTestClient(userId: '@mod:example.org');
        final room = buildTestRoom(client);
        setPowerLevels(room, {
          'users': {'@mod:example.org': 50, '@bob:example.org': 0},
        });
        expect(
          assignableRolesFor(room, targetUserId: '@bob:example.org'),
          unorderedEquals([RoomRole.readOnly, RoomRole.member]),
        );
      },
    );

    test('a moderator cannot touch a peer moderator or an admin', () {
      final client = buildTestClient(userId: '@mod:example.org');
      final room = buildTestRoom(client);
      setPowerLevels(room, {
        'users': {
          '@mod:example.org': 50,
          '@othermod:example.org': 50,
          '@admin:example.org': 100,
        },
      });
      expect(
        assignableRolesFor(room, targetUserId: '@othermod:example.org'),
        isEmpty,
      );
      expect(
        assignableRolesFor(room, targetUserId: '@admin:example.org'),
        isEmpty,
      );
    });

    test('a member or read-only user cannot assign any role', () {
      final client = buildTestClient(userId: '@member:example.org');
      final room = buildTestRoom(client);
      setPowerLevels(room, {
        'users': {'@member:example.org': 0, '@ro:example.org': -1},
      });
      expect(
        assignableRolesFor(room, targetUserId: '@ro:example.org'),
        isEmpty,
      );
    });

    test('nobody can assign themselves a role through this', () {
      final client = buildTestClient(userId: '@admin:example.org');
      final room = buildTestRoom(client);
      setPowerLevels(room, {
        'users': {'@admin:example.org': 100},
      });
      expect(
        assignableRolesFor(room, targetUserId: '@admin:example.org'),
        isEmpty,
      );
    });
  });

  group('canManageMember', () {
    test('a lower-level target is manageable', () {
      final client = buildTestClient(userId: '@admin:example.org');
      final room = buildTestRoom(client);
      setPowerLevels(room, {
        'users': {'@admin:example.org': 100, '@bob:example.org': 0},
      });
      expect(canManageMember(room, '@bob:example.org'), isTrue);
    });

    test('a peer or superior target is not manageable', () {
      final client = buildTestClient(userId: '@mod:example.org');
      final room = buildTestRoom(client);
      setPowerLevels(room, {
        'users': {
          '@mod:example.org': 50,
          '@othermod:example.org': 50,
          '@admin:example.org': 100,
        },
      });
      expect(canManageMember(room, '@othermod:example.org'), isFalse);
      expect(canManageMember(room, '@admin:example.org'), isFalse);
    });

    test('you can never manage yourself', () {
      final client = buildTestClient(userId: '@admin:example.org');
      final room = buildTestRoom(client);
      setPowerLevels(room, {
        'users': {'@admin:example.org': 100},
      });
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
}
