import 'package:matrix/matrix.dart';

import '../errors/caught_errors.dart';
import '../l10n/l10n.dart';
import 'optimistic_room_state.dart';
import 'room_permission.dart';

enum RoomRole { readOnly, member, moderator, admin }

extension RoomRoleX on RoomRole {
  int get powerLevel => switch (this) {
    RoomRole.readOnly => -1,
    RoomRole.member => 0,
    RoomRole.moderator => 50,
    RoomRole.admin => 100,
  };

  String label(AppLocalizations l10n) => switch (this) {
    RoomRole.readOnly => l10n.matrixRoleReadOnly,
    RoomRole.member => l10n.matrixRoleMember,
    RoomRole.moderator => l10n.matrixRoleModerator,
    RoomRole.admin => l10n.matrixRoleAdmin,
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

bool canManageMember(Room room, String targetUserId, {String? actorId}) =>
    memberManager(room, actorId: actorId)(targetUserId);

bool Function(String targetUserId) memberManager(Room room, {String? actorId}) {
  final actor = actorId ?? room.client.userID;
  if (actor == null) return (_) => false;
  final actorLevel = room.getPowerLevelByUserId(actor).level;
  return (targetUserId) =>
      targetUserId != actor &&
      room.getPowerLevelByUserId(targetUserId).level < actorLevel;
}

bool canRemoveMember(Room room, String targetUserId, {String? actorId}) =>
    memberRemover(room, actorId: actorId)(targetUserId);

bool Function(String targetUserId) memberRemover(Room room, {String? actorId}) {
  final mayRemove = actorId == null
      ? room.canKick
      : hasRoomPermission(room, actorId, 'kick');
  return mayRemove ? memberManager(room, actorId: actorId) : (_) => false;
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

String? memberBadge(Room room, User user, AppLocalizations l10n) {
  if (user.membership == Membership.invite) return l10n.matrixBadgeInvited;
  if (isRoomOwner(room, user.id)) return l10n.matrixBadgeOwner;
  return switch (ownRoomRole(room)) {
    RoomRole.admin ||
    RoomRole.moderator => roomRoleOfUser(room, user.id).label(l10n),
    RoomRole.member || RoomRole.readOnly => null,
  };
}
