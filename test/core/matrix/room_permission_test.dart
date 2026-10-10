import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/communities.dart';
import 'package:zuno/core/matrix/room_permission.dart';
import 'package:zuno/core/matrix/room_roles.dart';

import '../../helpers/fake_matrix.dart';

RoomPermission _find(String id) =>
    roomPermissions.firstWhere((p) => p.id == id);

void main() {
  test('calls and live location map to their state events', () {
    for (final (id, eventType) in [
      ('calls', 'm.call.member'),
      ('live_location', 'im.zuno.live_location'),
    ]) {
      final permission = _find(id);
      expect(
        permission.read({
          'events': {eventType: 0},
        }),
        0,
        reason: id,
      );
      final content = <String, Object?>{};
      permission.write(content, 50);
      expect(content, {
        'events': {eventType: 50},
      }, reason: id);
    }
  });

  test('the default role reads users_default, falling back to 0', () {
    expect(roomDefaultRoleSetting.read({}), 0);
    expect(roomDefaultRoleSetting.read({'users_default': 50}), 50);
  });

  group('setRoomPermissionLevel', () {
    test('the new value is readable immediately, before any sync', () async {
      final httpClient = MockClient(
        (request) async =>
            http.Response(jsonEncode({'event_id': r'$evt'}), 200),
      );
      final client =
          buildTestClient(userId: '@admin:example.org', httpClient: httpClient)
            ..homeserver = Uri.parse('https://example.org')
            ..accessToken = 'test-token';
      final room = buildTestRoom(client);
      expect(
        _find('invite')
            .read(room.getState(EventTypes.RoomPowerLevels)?.content ?? {}),
        0,
      );

      await setRoomPermissionLevel(room, _find('invite'), 50);

      expect(
        _find('invite')
            .read(room.getState(EventTypes.RoomPowerLevels)?.content ?? {}),
        50,
      );
    });
  });

  group('defaultGroupPowerLevels', () {
    test('matches this app\'s chosen defaults for a new group', () {
      final content = defaultGroupPowerLevels();
      RoomRole levelFor(String id) => roomRoleForLevel(_find(id).read(content));

      expect(levelFor('room_avatar'), RoomRole.admin);
      expect(levelFor('room_name'), RoomRole.admin);
      expect(levelFor('room_topic'), RoomRole.admin);
      expect(levelFor('canonical_alias'), RoomRole.admin);
      expect(levelFor('invite'), RoomRole.member);
      expect(levelFor('kick'), RoomRole.moderator);
      expect(levelFor('ban'), RoomRole.moderator);
      expect(levelFor('events_default'), RoomRole.member);
      expect(levelFor('calls'), RoomRole.member);
      expect(levelFor('live_location'), RoomRole.member);
      expect(levelFor('redact'), RoomRole.moderator);
      expect(levelFor('notify_room'), RoomRole.moderator);
      expect(levelFor('state_default'), RoomRole.admin);
      expect(levelFor('history_visibility'), RoomRole.admin);
      expect(levelFor('power_levels'), RoomRole.admin);
      expect(levelFor('encryption'), RoomRole.admin);
    });

    test('leaves users_default unset', () {
      expect(defaultGroupPowerLevels().containsKey('users_default'), isFalse);
      expect(
        defaultGroupPowerLevels(public: true).containsKey('users_default'),
        isFalse,
      );
    });

    test('a public room keeps calls and live location for moderators and '
        'changes nothing else', () {
      final private = defaultGroupPowerLevels();
      final public = defaultGroupPowerLevels(public: true);

      expect(roomRoleForLevel(_find('calls').read(public)), RoomRole.moderator);
      expect(
        roomRoleForLevel(_find('live_location').read(public)),
        RoomRole.moderator,
      );
      for (final permission in roomPermissions) {
        if (permission.id == 'calls' || permission.id == 'live_location') {
          continue;
        }
        expect(
          permission.read(public),
          permission.read(private),
          reason: permission.id,
        );
      }
    });
  });

  group('read()', () {
    test('a state-event override falls back to state_default when unset', () {
      expect(_find('room_name').read({'state_default': 50}), 50);
      expect(_find('room_name').read({}), 50);
    });

    test('a state-event override wins over state_default when set', () {
      expect(
        _find('room_name').read({
          'state_default': 50,
          'events': {EventTypes.RoomName: 0},
        }),
        0,
      );
    });

    test('direct fields fall back to the SDK-documented defaults', () {
      expect(_find('invite').read({}), 0);
      expect(_find('kick').read({}), 50);
      expect(_find('ban').read({}), 50);
      expect(_find('events_default').read({}), 0);
      expect(_find('redact').read({}), 50);
      expect(_find('state_default').read({}), 50);
    });

    test('a nested notifications field falls back correctly', () {
      expect(_find('notify_room').read({}), 50);
      expect(
        _find('notify_room').read({
          'notifications': {'room': 0},
        }),
        0,
      );
    });
  });

  group('write()', () {
    test('a state-event override sets it without clobbering sibling event overrides', () {
      final content = <String, Object?>{
        'events': {EventTypes.RoomTopic: 50},
      };
      _find('room_name').write(content, 0);
      expect(content['events'], {
        EventTypes.RoomTopic: 50,
        EventTypes.RoomName: 0,
      });
    });

    test('a direct field just sets the key', () {
      final content = <String, Object?>{'ban': 50};
      _find('kick').write(content, 0);
      expect(content, {'ban': 50, 'kick': 0});
    });

    test('a nested notifications field is set without clobbering siblings', () {
      final content = <String, Object?>{
        'notifications': {'other': 1},
      };
      _find('notify_room').write(content, 100);
      expect(content['notifications'], {'other': 1, 'room': 100});
    });
  });

  group('roomPermissionsAccessFor', () {
    for (final (name, level, access) in [
      ('an admin can edit', 100, RoomPermissionsAccess.edit),
      ('a moderator can only read', 50, RoomPermissionsAccess.readOnly),
      ('a plain member sees nothing', 0, RoomPermissionsAccess.hidden),
      ('a read-only member sees nothing', -1, RoomPermissionsAccess.hidden),
    ]) {
      test(name, () {
        final room = buildTestRoom(buildTestClient(userId: '@me:example.org'));
        room.setState(
          buildTestEvent(
            room,
            eventId: r'$powerlevels',
            senderId: '@creator:example.org',
            type: EventTypes.RoomPowerLevels,
            stateKey: '',
            content: {
              'users': {'@me:example.org': level},
            },
          ),
        );

        expect(roomPermissionsAccessFor(room), access);
      });
    }
  });

  group('community rules', () {
    test('cover members, rooms and settings, and nothing a community '
        'lacks', () {
      expect(communityPermissionGroups.map((g) => g.title), [
        'Members',
        'Rooms',
        'Settings',
      ]);
      final labels = [
        for (final group in communityPermissionGroups)
          for (final permission in group.permissions) permission.label,
      ];
      expect(labels, [
        'Invite people',
        'Remove people',
        'Ban people',
        'Add rooms',
        'Change photo',
        'Change name',
        'Change description',
        'Change permissions',
      ]);
    });

    test('read what a new community starts with', () {
      RoomRole roleOf(String label) {
        final permission = [
          for (final group in communityPermissionGroups) ...group.permissions,
        ].firstWhere((p) => p.label == label);
        return roomRoleForLevel(permission.read(communityPowerLevels));
      }

      expect(roleOf('Invite people'), RoomRole.member);
      expect(roleOf('Remove people'), RoomRole.moderator);
      expect(roleOf('Ban people'), RoomRole.moderator);
      expect(roleOf('Add rooms'), RoomRole.moderator);
      expect(roleOf('Change photo'), RoomRole.admin);
      expect(roleOf('Change name'), RoomRole.admin);
      expect(roleOf('Change description'), RoomRole.admin);
      expect(roleOf('Change permissions'), RoomRole.admin);
    });

    test('adding rooms writes the space child level', () {
      final addRooms = communityPermissionGroups
          .expand((g) => g.permissions)
          .firstWhere((p) => p.label == 'Add rooms');
      final content = <String, Object?>{'events': <String, Object?>{}};

      addRooms.write(content, RoomRole.member.powerLevel);

      expect((content['events']! as Map)[EventTypes.SpaceChild], 0);
    });
  });
}
