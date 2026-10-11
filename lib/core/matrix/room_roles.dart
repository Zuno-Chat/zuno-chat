import 'package:matrix/matrix.dart';

import '../errors/caught_errors.dart';
import 'optimistic_room_state.dart';

enum RoomRole { readOnly, member, moderator, admin }

extension RoomRoleX on RoomRole {
  int get powerLevel => switch (this) {
    RoomRole.readOnly => -1,
    RoomRole.member => 0,
    RoomRole.moderator => 50,
    RoomRole.admin => 100,
  };

  String get label => switch (this) {
    RoomRole.readOnly => 'Read-only',
    RoomRole.member => 'Member',
    RoomRole.moderator => 'Moderator',
    RoomRole.admin => 'Admin',
  };
}

RoomRole roomRoleForLevel(int level) {
  if (level >= RoomRole.admin.powerLevel) return RoomRole.admin;
  if (level >= RoomRole.moderator.powerLevel) return RoomRole.moderator;
  if (level >= RoomRole.member.powerLevel) return RoomRole.member;
  return RoomRole.readOnly;
}

RoomRole ownRoomRole(Room room) => roomRoleForLevel(room.ownPowerLevel.level);

RoomRole roomRoleOfUser(Room room, String userId) =>
    roomRoleForLevel(room.getPowerLevelByUserId(userId).level);

bool canManageMember(Room room, String targetUserId) {
  if (targetUserId == room.client.userID) return false;
  return room.getPowerLevelByUserId(targetUserId).level <
      room.ownPowerLevel.level;
}

List<RoomRole> assignableRolesFor(Room room, {required String targetUserId}) {
  if (!room.canChangePowerLevel || !canManageMember(room, targetUserId)) {
    return const [];
  }

  return switch (ownRoomRole(room)) {
    RoomRole.admin => RoomRole.values,
    RoomRole.moderator => const [RoomRole.readOnly, RoomRole.member],
    RoomRole.member || RoomRole.readOnly => const [],
  };
}

Future<bool> isLastAdmin(Room room) async {
  final me = room.client.userID;
  if (me == null || ownRoomRole(room) != RoomRole.admin) return false;
  if ((room.summary.mJoinedMemberCount ?? 0) < 2) return false;
  final powerLevels = room.getState(EventTypes.RoomPowerLevels)?.content;
  final everyone = powerLevels?.tryGet<int>('users_default') ?? 0;
  if (roomRoleForLevel(everyone) == RoomRole.admin) return false;
  final others = {
    ...?powerLevels?.tryGetMap<String, Object?>('users')?.keys,
    ...room.creatorUserIds,
  }..remove(me);
  for (final id in others) {
    if (roomRoleOfUser(room, id) != RoomRole.admin) continue;
    final membership = (await _memberOf(room, id))?.content['membership'];
    if (membership == null || membership == 'join' || membership == 'invite') {
      return false;
    }
  }
  return true;
}

Future<StrippedStateEvent?> _memberOf(Room room, String userId) async {
  final known = room.getState(EventTypes.RoomMember, userId);
  if (known != null) return known;
  try {
    return await room.client.database.getUser(userId, room);
  } catch (e, s) {
    reportCaught('read a member for the last admin check', e, s);
    return null;
  }
}

List<String> bannedUserIds(Room room) {
  final members = room.states[EventTypes.RoomMember] ?? const {};
  return [
    for (final entry in members.entries)
      if (entry.value.content['membership'] == 'ban') entry.key,
  ];
}

Future<void> setUserRoomRole(Room room, String userId, RoomRole role) async {
  final content = Map<String, Object?>.from(
    room.getState(EventTypes.RoomPowerLevels)?.content ?? {},
  );
  final users = Map<String, Object?>.from(
    (content['users'] as Map?)?.cast<String, Object?>() ?? {},
  );
  users[userId] = role.powerLevel;
  content['users'] = users;
  await room.client.setRoomStateWithKey(
    room.id,
    EventTypes.RoomPowerLevels,
    '',
    content,
  );
  applyOptimisticRoomState(room, EventTypes.RoomPowerLevels, content);
}

bool isRoomOwner(Room room, String userId) =>
    room.creatorUserIds.contains(userId);

bool canSeeAdvancedRoomInfo(Room room) {
  final userId = room.client.userID;
  if (userId != null && isRoomOwner(room, userId)) return true;
  return ownRoomRole(room) == RoomRole.admin;
}

List<User> membersOwnerFirst(Room room, List<User> users) => [
  for (final user in users)
    if (isRoomOwner(room, user.id)) user,
  for (final user in users)
    if (!isRoomOwner(room, user.id)) user,
];

String? memberBadge(Room room, User user) {
  if (user.membership == Membership.invite) return 'Invited';
  if (isRoomOwner(room, user.id)) return 'Owner';
  return switch (ownRoomRole(room)) {
    RoomRole.admin || RoomRole.moderator => roomRoleOfUser(room, user.id).label,
    RoomRole.member || RoomRole.readOnly => null,
  };
}
