import 'package:matrix/matrix.dart';

import '../l10n/l10n.dart';
import '../location/live_location_protocol.dart';
import 'optimistic_room_state.dart';
import 'room_roles.dart';

typedef LocalizedText = String Function(AppLocalizations l10n);

enum RoomPermissionSection { basic, advanced }

class RoomPermission {
  final String id;
  final LocalizedText label;
  final RoomPermissionSection section;
  final int Function(Map<String, Object?> content) read;
  final void Function(Map<String, Object?> content, int level) write;

  const RoomPermission({
    required this.id,
    required this.label,
    required this.section,
    required this.read,
    required this.write,
  });
}

Map<String, Object?> _nestedMap(Map<String, Object?> content, String key) =>
    Map<String, Object?>.from(
      (content[key] as Map?)?.cast<String, Object?>() ?? {},
    );

RoomPermission _stateEventOverride(
  String id,
  LocalizedText label,
  String eventType, {
  RoomPermissionSection section = RoomPermissionSection.advanced,
}) => RoomPermission(
  id: id,
  label: label,
  section: section,
  read: (c) =>
      _nestedMap(c, 'events')[eventType] as int? ??
      c['state_default'] as int? ??
      50,
  write: (c, level) {
    final events = _nestedMap(c, 'events');
    events[eventType] = level;
    c['events'] = events;
  },
);

RoomPermission _directField(
  String id,
  LocalizedText label,
  String field, {
  required int fallback,
  RoomPermissionSection section = RoomPermissionSection.advanced,
}) => RoomPermission(
  id: id,
  label: label,
  section: section,
  read: (c) => c[field] as int? ?? fallback,
  write: (c, level) => c[field] = level,
);

RoomPermission _notificationField(
  String id,
  LocalizedText label,
  String type, {
  required int fallback,
}) => RoomPermission(
  id: id,
  label: label,
  section: RoomPermissionSection.advanced,
  read: (c) => _nestedMap(c, 'notifications')[type] as int? ?? fallback,
  write: (c, level) {
    final notifications = _nestedMap(c, 'notifications');
    notifications[type] = level;
    c['notifications'] = notifications;
  },
);

final List<RoomPermission> roomPermissions = [
  _stateEventOverride(
    'room_avatar',
    (l10n) => l10n.matrixPermissionRoomAvatar,
    EventTypes.RoomAvatar,
    section: RoomPermissionSection.basic,
  ),
  _stateEventOverride(
    'room_name',
    (l10n) => l10n.matrixPermissionRoomName,
    EventTypes.RoomName,
    section: RoomPermissionSection.basic,
  ),
  _stateEventOverride(
    'room_topic',
    (l10n) => l10n.matrixPermissionRoomTopic,
    EventTypes.RoomTopic,
    section: RoomPermissionSection.basic,
  ),
  _stateEventOverride(
    'canonical_alias',
    (l10n) => l10n.matrixPermissionCanonicalAlias,
    EventTypes.RoomCanonicalAlias,
  ),
  _directField(
    'invite',
    (l10n) => l10n.matrixPermissionInvite,
    'invite',
    fallback: 0,
  ),
  _directField(
    'kick',
    (l10n) => l10n.matrixPermissionKick,
    'kick',
    fallback: 50,
  ),
  _directField('ban', (l10n) => l10n.matrixPermissionBan, 'ban', fallback: 50),
  _directField(
    'events_default',
    (l10n) => l10n.matrixPermissionEventsDefault,
    'events_default',
    fallback: 0,
  ),
  _stateEventOverride(
    'calls',
    (l10n) => l10n.matrixPermissionCalls,
    'm.call.member',
  ),
  _stateEventOverride(
    'live_location',
    (l10n) => l10n.matrixPermissionLiveLocation,
    liveLocationStateType,
  ),
  _directField(
    'redact',
    (l10n) => l10n.matrixPermissionRedact,
    'redact',
    fallback: 50,
  ),
  _notificationField(
    'notify_room',
    (l10n) => l10n.matrixPermissionNotifyRoom,
    'room',
    fallback: 50,
  ),
  _directField(
    'state_default',
    (l10n) => l10n.matrixPermissionStateDefault,
    'state_default',
    fallback: 50,
  ),
  _stateEventOverride(
    'history_visibility',
    (l10n) => l10n.matrixPermissionHistoryVisibility,
    EventTypes.HistoryVisibility,
  ),
  _stateEventOverride(
    'power_levels',
    (l10n) => l10n.matrixPermissionPowerLevels,
    EventTypes.RoomPowerLevels,
  ),
  _stateEventOverride(
    'encryption',
    (l10n) => l10n.matrixPermissionEncryption,
    EventTypes.Encryption,
  ),
];

typedef PermissionGroup = ({
  LocalizedText title,
  List<RoomPermission> permissions,
});

RoomPermission _catalogEntry(String id) =>
    roomPermissions.firstWhere((permission) => permission.id == id);

bool hasRoomPermission(Room room, String userId, String permissionId) {
  final content =
      room.getState(EventTypes.RoomPowerLevels)?.content ??
      const <String, Object?>{};
  return room.getPowerLevelByUserId(userId).level >=
      _catalogEntry(permissionId).read(content);
}

final List<PermissionGroup> roomPermissionGroups = [
  for (final (title, section) in <(LocalizedText, RoomPermissionSection)>[
    ((l10n) => l10n.matrixPermissionGroupBasic, RoomPermissionSection.basic),
    (
      (l10n) => l10n.matrixPermissionGroupAdvanced,
      RoomPermissionSection.advanced,
    ),
  ])
    (
      title: title,
      permissions: [
        for (final permission in roomPermissions)
          if (permission.section == section) permission,
      ],
    ),
];

final List<PermissionGroup> communityPermissionGroups = [
  (
    title: (l10n) => l10n.matrixPermissionGroupMembers,
    permissions: [
      _catalogEntry('invite'),
      _catalogEntry('kick'),
      _catalogEntry('ban'),
    ],
  ),
  (
    title: (l10n) => l10n.matrixPermissionGroupRooms,
    permissions: [
      _stateEventOverride(
        'add_rooms',
        (l10n) => l10n.matrixPermissionAddRooms,
        EventTypes.SpaceChild,
      ),
    ],
  ),
  (
    title: (l10n) => l10n.matrixPermissionGroupSettings,
    permissions: [
      _stateEventOverride(
        'community_avatar',
        (l10n) => l10n.matrixPermissionCommunityAvatar,
        EventTypes.RoomAvatar,
      ),
      _stateEventOverride(
        'community_name',
        (l10n) => l10n.matrixPermissionCommunityName,
        EventTypes.RoomName,
      ),
      _stateEventOverride(
        'community_topic',
        (l10n) => l10n.matrixPermissionCommunityTopic,
        EventTypes.RoomTopic,
      ),
      _catalogEntry('power_levels'),
    ],
  ),
];

final RoomPermission roomDefaultRoleSetting = _directField(
  'users_default',
  (l10n) => l10n.matrixPermissionUsersDefault,
  'users_default',
  fallback: 0,
);

const Map<String, RoomRole> _defaultGroupPermissionRoles = {
  'room_avatar': RoomRole.admin,
  'room_name': RoomRole.admin,
  'room_topic': RoomRole.admin,
  'canonical_alias': RoomRole.admin,
  'invite': RoomRole.member,
  'kick': RoomRole.moderator,
  'ban': RoomRole.moderator,
  'events_default': RoomRole.member,
  'calls': RoomRole.member,
  'live_location': RoomRole.member,
  'redact': RoomRole.moderator,
  'notify_room': RoomRole.moderator,
  'state_default': RoomRole.admin,
  'history_visibility': RoomRole.admin,
  'power_levels': RoomRole.admin,
  'encryption': RoomRole.admin,
};

const Map<String, RoomRole> _publicRoomPermissionRoles = {
  'calls': RoomRole.moderator,
  'live_location': RoomRole.moderator,
};

Map<String, dynamic> defaultGroupPowerLevels({bool public = false}) {
  assert(
    roomPermissions.every(
          (p) => _defaultGroupPermissionRoles.containsKey(p.id),
        ) &&
        _defaultGroupPermissionRoles.length == roomPermissions.length &&
        _publicRoomPermissionRoles.keys.every(
          _defaultGroupPermissionRoles.containsKey,
        ),
    'defaultGroupPermissionRoles must cover exactly roomPermissions, and '
    'publicRoomPermissionRoles may only name those',
  );
  final roles = public
      ? {..._defaultGroupPermissionRoles, ..._publicRoomPermissionRoles}
      : _defaultGroupPermissionRoles;
  final content = <String, Object?>{};
  for (final permission in roomPermissions) {
    final role = roles[permission.id];
    if (role != null) permission.write(content, role.powerLevel);
  }
  return content;
}

Future<void> setRoomPermissionLevel(
  Room room,
  RoomPermission permission,
  int level,
) async {
  final content = Map<String, Object?>.from(
    room.getState(EventTypes.RoomPowerLevels)?.content ?? {},
  );
  permission.write(content, level);
  await room.client.setRoomStateWithKey(
    room.id,
    EventTypes.RoomPowerLevels,
    '',
    content,
  );
  applyOptimisticRoomState(room, EventTypes.RoomPowerLevels, content);
}

enum RoomPermissionsAccess { edit, readOnly, hidden }

RoomPermissionsAccess roomPermissionsAccessFor(Room room) =>
    switch (ownRoomRole(room)) {
      RoomRole.admin => RoomPermissionsAccess.edit,
      RoomRole.moderator => RoomPermissionsAccess.readOnly,
      RoomRole.member || RoomRole.readOnly => RoomPermissionsAccess.hidden,
    };

bool canPostInRoom(Room room) =>
    room.canSendDefaultMessages && !room.isAbandonedDMRoom;
