import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/calls/end_call.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/rooms/abuse_report.dart';
import '../../../core/matrix/rooms/optimistic_room_state.dart';
import '../../../core/matrix/rooms/permissions/room_roles.dart';
import '../../../core/matrix/rooms/room_access.dart';
import '../../../core/ui/notice.dart';
import '../../blocking/presentation/block_person.dart';
import '../../chat/presentation/room_page.dart';
import '../../reports/presentation/report_sheet.dart';
import 'remove_member_dialog.dart';
import 'role_picker.dart';

enum MemberAction {
  message(Icons.chat_bubble_outline),
  changeRole(Icons.badge_outlined, moderates: true),
  remove(Icons.person_remove_outlined, moderates: true),
  ban(Icons.block_outlined, moderates: true),
  block(Icons.do_not_disturb_on_outlined),
  unblock(Icons.do_not_disturb_off_outlined),
  report(Icons.flag_outlined);

  final IconData icon;
  final bool moderates;

  const MemberAction(this.icon, {this.moderates = false});

  String label(AppLocalizations l10n, Room room) {
    final community = room.isSpace;
    return switch (this) {
      message => l10n.roomInfoMessagePerson,
      changeRole => l10n.commonChangeRole,
      remove =>
        community
            ? l10n.communitiesRemoveFromCommunity
            : l10n.roomInfoRemoveFromRoom,
      ban =>
        community ? l10n.communitiesBanFromCommunity : l10n.roomInfoBanFromRoom,
      block => l10n.commonBlock,
      unblock => l10n.blockingUnblock,
      report => l10n.commonReport,
    };
  }
}

RemoveMemberPlace _placeOf(Room room) =>
    room.isSpace ? RemoveMemberPlace.community : RemoveMemberPlace.room;

List<MemberAction> memberActionsFor(Room room, User user) {
  if (room.isDirectChat ||
      user.id == room.client.userID ||
      user.membership != Membership.join) {
    return const [];
  }
  final moderation = [
    if (assignableRolesFor(room, targetUserId: user.id).isNotEmpty)
      MemberAction.changeRole,
    if (canRemoveMember(room, user.id)) MemberAction.remove,
    if (canManageMember(room, user.id) && room.canBan) MemberAction.ban,
  ];
  if (room.isSpace) return moderation;
  return [
    MemberAction.message,
    ...moderation,
    if (canBlockPerson(user.id))
      room.client.ignoredUsers.contains(user.id)
          ? MemberAction.unblock
          : MemberAction.block,
    MemberAction.report,
  ];
}

Future<bool> actOnMember(
  BuildContext context,
  WidgetRef ref,
  Room room,
  User user,
  MemberAction action, {
  BlockPerson? blockPerson,
  UnblockPerson? unblockPerson,
}) {
  final name = user.calcDisplayname();
  return switch (action) {
    MemberAction.message => _messagePerson(context, room.client, user.id),
    MemberAction.changeRole => _changeMemberRole(context, room, user),
    MemberAction.remove => _removeMember(context, room, user, ban: false),
    MemberAction.ban => _removeMember(context, room, user, ban: true),
    MemberAction.block => blockAndReturnHome(
      context,
      client: room.client,
      userId: user.id,
      name: name,
      endCallsIn: ref.read(endCallsInProvider),
      block: blockPerson,
    ),
    MemberAction.unblock => unblockAndReturnHome(
      context,
      client: room.client,
      userId: user.id,
      name: name,
      unblock: unblockPerson,
    ),
    MemberAction.report => reportPersonIn(
      context,
      room,
      userId: user.id,
      name: name,
    ),
  };
}

Future<bool> _messagePerson(
  BuildContext context,
  Client client,
  String userId,
) async {
  final navigator = Navigator.of(context);
  String? roomId;
  final started = await attempt(
    context,
    () async => roomId = await startEncryptedDirectChat(client, userId),
    label: 'start chat',
    failed: context.l10n.roomsCouldNotStartChat,
  );
  final chat = started ? client.getRoomById(roomId!) : null;
  if (chat == null) return false;
  openChat(navigator, chat);
  return true;
}

Future<bool> reportPersonIn(
  BuildContext context,
  Room room, {
  required String userId,
  required String name,
}) {
  final l10n = context.l10n;
  return showReportSheet(
    context,
    title: l10n.roomInfoReportPerson(name),
    explanation: room.isDirectChat
        ? l10n.roomInfoReportExplainDirect
        : l10n.roomInfoReportExplainGroup,
    onSend: (reason, note) =>
        reportPerson(room.client, userId, reason, note: note, roomId: room.id),
  );
}

Future<bool> _changeMemberRole(
  BuildContext context,
  Room room,
  User user,
) async {
  final current = roomRoleOfUser(room, user.id);
  final chosen = await showRolePicker(
    context,
    current: current,
    options: assignableRolesFor(room, targetUserId: user.id),
  );
  if (chosen == null || chosen == current || !context.mounted) return false;
  return attempt(
    context,
    () => setUserRoomRole(room, user.id, chosen),
    label: 'change role',
    failed: context.l10n.commonRoleNotChanged,
  );
}

Future<bool> _removeMember(
  BuildContext context,
  Room room,
  User user, {
  required bool ban,
}) async {
  final confirmed = await confirmRemoveMember(
    context,
    name: user.calcDisplayname(),
    ban: ban,
    place: _placeOf(room),
  );
  if (!confirmed || !context.mounted) return false;
  final l10n = context.l10n;
  return attempt(
    context,
    () async {
      await (ban ? room.ban(user.id) : room.kick(user.id));
      applyOptimisticMembership(
        room,
        user.id,
        ban ? Membership.ban : Membership.leave,
      );
    },
    label: ban ? 'ban member' : 'remove member',
    failed: ban ? l10n.commonMemberNotBanned : l10n.commonMemberNotRemoved,
  );
}
