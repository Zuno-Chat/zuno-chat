import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/room_permission.dart';
import 'package:zuno/core/matrix/room_roles.dart';

import '../../helpers/fake_matrix.dart';

RoomPermission _find(String id) =>
    roomPermissions.firstWhere((p) => p.id == id);

void main() {
  group('catalog', () {
    test('has exactly 15 entries: 3 basic + 12 advanced', () {
      expect(roomPermissions, hasLength(15));
      expect(
        roomPermissions.where((p) => p.section == RoomPermissionSection.basic),
        hasLength(3),
      );
      expect(
        roomPermissions.where(
          (p) => p.section == RoomPermissionSection.advanced,
        ),
        hasLength(12),
      );
    });

    test('every id is unique', () {
      final ids = roomPermissions.map((p) => p.id).toSet();
      expect(ids, hasLength(roomPermissions.length));
    });

    test('does not include users_default', () {
      expect(roomPermissions.where((p) => p.id == 'users_default'), isEmpty);
    });

    test('no longer includes widgets, server_acl, or tombstone', () {
      final ids = roomPermissions.map((p) => p.id).toSet();
      expect(ids, isNot(contains('widgets')));
      expect(ids, isNot(contains('server_acl')));
      expect(ids, isNot(contains('tombstone')));
    });

    test('includes calls, mapped to m.call.member', () {
      final permission = _find('calls');
      expect(
        permission.read({
          'events': {'m.call.member': 0},
        }),
        0,
      );
      final content = <String, Object?>{};
      permission.write(content, 50);
      expect(content, {
        'events': {'m.call.member': 50},
      });
    });
  });

  group('roomDefaultRoleSetting', () {
    test('reads users_default directly, falling back to 0', () {
      expect(roomDefaultRoleSetting.read({}), 0);
      expect(roomDefaultRoleSetting.read({'users_default': 50}), 50);
    });

    test('write() just sets the key', () {
      final content = <String, Object?>{'ban': 50};
      roomDefaultRoleSetting.write(content, -1);
      expect(content, {'ban': 50, 'users_default': -1});
    });
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

    test('a public room keeps calls for moderators and changes nothing '
        'else', () {
      final private = defaultGroupPowerLevels();
      final public = defaultGroupPowerLevels(public: true);

      expect(roomRoleForLevel(_find('calls').read(public)), RoomRole.moderator);
      for (final permission in roomPermissions) {
        if (permission.id == 'calls') continue;
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

    test('an admin can edit', () {
      final client = buildTestClient(userId: '@admin:example.org');
      final room = buildTestRoom(client);
      setPowerLevels(room, {
        'users': {'@admin:example.org': 100},
      });
      expect(roomPermissionsAccessFor(room), RoomPermissionsAccess.edit);
    });

    test('a moderator can only read', () {
      final client = buildTestClient(userId: '@mod:example.org');
      final room = buildTestRoom(client);
      setPowerLevels(room, {
        'users': {'@mod:example.org': 50},
      });
      expect(roomPermissionsAccessFor(room), RoomPermissionsAccess.readOnly);
    });

    test('a plain member sees nothing', () {
      final client = buildTestClient(userId: '@member:example.org');
      final room = buildTestRoom(client);
      setPowerLevels(room, {
        'users': {'@member:example.org': 0},
      });
      expect(roomPermissionsAccessFor(room), RoomPermissionsAccess.hidden);
    });

    test('a read-only member sees nothing', () {
      final client = buildTestClient(userId: '@ro:example.org');
      final room = buildTestRoom(client);
      setPowerLevels(room, {
        'users': {'@ro:example.org': -1},
      });
      expect(roomPermissionsAccessFor(room), RoomPermissionsAccess.hidden);
    });
  });
}
