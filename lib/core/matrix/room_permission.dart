import 'package:matrix/matrix.dart';

import 'optimistic_room_state.dart';
import 'room_roles.dart';

enum RoomPermissionSection { basic, advanced }

class RoomPermission {
  final String id;
  final String label;
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
  String label,
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
  String label,
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
  String label,
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
    'Change room photo',
    EventTypes.RoomAvatar,
    section: RoomPermissionSection.basic,
  ),
  _stateEventOverride(
    'room_name',
    'Change room name',
    EventTypes.RoomName,
    section: RoomPermissionSection.basic,
  ),
  _stateEventOverride(
    'room_topic',
    'Change topic',
    EventTypes.RoomTopic,
    section: RoomPermissionSection.basic,
  ),
  _stateEventOverride(
    'canonical_alias',
    'Change the room address',
    EventTypes.RoomCanonicalAlias,
  ),
  _directField('invite', 'Invite people', 'invite', fallback: 0),
  _directField('kick', 'Remove people', 'kick', fallback: 50),
  _directField('ban', 'Ban people', 'ban', fallback: 50),
  _directField(
    'events_default',
    'Send messages',
    'events_default',
    fallback: 0,
  ),
  _stateEventOverride('calls', 'Start or join calls', 'm.call.member'),
  _directField(
    'redact',
    "Delete other people's messages",
    'redact',
    fallback: 50,
  ),
  _notificationField('notify_room', 'Notify everyone', 'room', fallback: 50),
  _directField(
    'state_default',
    'Change settings',
    'state_default',
    fallback: 50,
  ),
  _stateEventOverride(
    'history_visibility',
    'Change who can read history',
    EventTypes.HistoryVisibility,
  ),
  _stateEventOverride(
    'power_levels',
    'Change permissions',
    EventTypes.RoomPowerLevels,
  ),
  _stateEventOverride(
    'encryption',
    'Turn on encryption',
    EventTypes.Encryption,
  ),
];

final RoomPermission roomDefaultRoleSetting = _directField(
  'users_default',
  'Default role for new members',
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
  'redact': RoomRole.moderator,
  'notify_room': RoomRole.moderator,
  'state_default': RoomRole.admin,
  'history_visibility': RoomRole.admin,
  'power_levels': RoomRole.admin,
  'encryption': RoomRole.admin,
};

const Map<String, RoomRole> _publicRoomPermissionRoles = {
  'calls': RoomRole.moderator,
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
