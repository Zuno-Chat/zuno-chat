import 'package:matrix/matrix.dart';

import 'matrix_ids.dart';
import 'room_exit.dart';
import 'room_title.dart';

bool isIncomingInvite(Room room) => room.membership == Membership.invite;

String? inviterId(Room room) {
  final ownMember = ownInviteMember(room);
  if (ownMember != null) return ownMember.senderId;
  final ownId = room.client.userID;
  final hero = (room.summary.mHeroes ?? []).firstWhere(
    (id) => id != ownId,
    orElse: () => '',
  );
  return hero.isEmpty ? null : hero;
}

StrippedStateEvent? ownInviteMember(Room room) {
  final ownId = room.client.userID;
  if (ownId == null) return null;
  final member = room.getState(EventTypes.RoomMember, ownId);
  if (member == null || member.senderId == ownId) return null;
  return member;
}

bool isDirectInvite(Room room) =>
    ownInviteMember(room)?.content['is_direct'] == true;

Future<void> loadInviteMembers(Room room) async {
  final ownId = room.client.userID;
  if (ownId == null || !isIncomingInvite(room)) return;

  final ownMember = ownInviteMember(room) ?? await _restoreMember(room, ownId);
  final inviter = ownMember?.senderId ?? inviterId(room);
  if (inviter == null || inviter == ownId) return;
  if (room.getState(EventTypes.RoomMember, inviter) == null) {
    await _restoreMember(room, inviter);
  }
}

Future<StrippedStateEvent?> _restoreMember(Room room, String userId) async {
  try {
    final user = await room.client.database.getUser(userId, room);
    if (user == null) return null;
    room.setState(user);
    return user;
  } catch (_) {
    return null;
  }
}

Future<void> acceptInvite(Room room) async {
  await loadInviteMembers(room);
  await room.join();
}

Future<void> declineInvite(Room room) async {
  await loadInviteMembers(room);
  await exitRoom(room, isDirect: isDirectInvite(room));
}

List<User> pendingInvitees(Room room) => room
    .getParticipants([Membership.invite])
    .where((user) => user.id != room.client.userID)
    .toList();

List<String> pendingInviteeIds(Room room) {
  final fromState = pendingInvitees(room).map((user) => user.id).toList();
  if (fromState.isNotEmpty) return fromState;
  return (room.summary.mHeroes ?? [])
      .where((id) => id != room.client.userID)
      .toList();
}

bool isAwaitingInviteAcceptance(Room room) {
  if (room.membership != Membership.join) return false;

  final invited = room.summary.mInvitedMemberCount;
  final joined = room.summary.mJoinedMemberCount;
  if (invited != null && joined != null) return invited > 0 && joined <= 1;

  if (pendingInvitees(room).isEmpty) return false;
  return !room
      .getParticipants([Membership.join])
      .any((user) => user.id != room.client.userID);
}

class RoomInviteDisplay {
  final String title;
  final Uri? avatarUrl;
  final bool awaitingAcceptance;
  final bool partnerLeft;

  const RoomInviteDisplay({
    required this.title,
    required this.avatarUrl,
    required this.awaitingAcceptance,
    required this.partnerLeft,
  });
}

RoomInviteDisplay roomInviteDisplay(Room room) {
  final awaiting = isAwaitingInviteAcceptance(room);
  if (awaiting && room.name.isEmpty) {
    final invitees = pendingInviteeIds(room);
    if (invitees.isNotEmpty) {
      return RoomInviteDisplay(
        title: invitees.length == 1
            ? withoutServer(invitees.single)
            : '${invitees.length} people invited',
        avatarUrl: null,
        awaitingAcceptance: true,
        partnerLeft: false,
      );
    }
  }
  return RoomInviteDisplay(
    title: roomTitle(room),
    avatarUrl: room.avatar,
    awaitingAcceptance: awaiting,
    partnerLeft: room.isAbandonedDMRoom,
  );
}

String pendingInviteSubtitle(Room room) {
  final invitees = pendingInviteeIds(room);
  if (invitees.length == 1) {
    return 'Waiting for ${withoutServer(invitees.single)} to accept';
  }
  if (invitees.isEmpty) return 'Waiting for them to accept';
  return 'Waiting for ${invitees.length} people to accept';
}
