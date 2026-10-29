import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/optimistic_room_state.dart';
import '../../../core/matrix/room_roles.dart';
import '../../../core/ui/notice.dart';
import '../../../core/ui/sheet.dart';
import '../../blocking/presentation/block_person.dart';
import 'remove_member_dialog.dart';
import 'role_picker.dart';

enum MemberAction {
  message(Icons.chat_bubble_outline),
  changeRole(Icons.badge_outlined),
  remove(Icons.person_remove_outlined),
  ban(Icons.block_outlined),
  block(Icons.do_not_disturb_on_outlined),
  report(Icons.flag_outlined);

  final IconData icon;

  const MemberAction(this.icon);

  String label(AppLocalizations l10n, RemoveMemberPlace place) {
    final community = place == RemoveMemberPlace.community;
    return switch (this) {
      message => l10n.roomInfoStartChat,
      changeRole => l10n.commonChangeRole,
      remove =>
        community
            ? l10n.communitiesRemoveFromCommunity
            : l10n.roomInfoRemoveFromRoom,
      ban =>
        community ? l10n.communitiesBanFromCommunity : l10n.roomInfoBanFromRoom,
      block => l10n.commonBlock,
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
    if (canBlockPerson(user.id)) MemberAction.block,
    MemberAction.report,
  ];
}

Future<MemberAction?> chooseMemberAction(
  BuildContext context,
  Room room,
  User user,
) {
  final l10n = context.l10n;
  final place = _placeOf(room);
  return showActionSheet(
    context,
    actions: [
      for (final action in memberActionsFor(room, user))
        SheetAction(
          action,
          icon: action.icon,
          label: action.label(l10n, place),
        ),
    ],
  );
}

Future<bool> changeMemberRole(
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

Future<bool> removeMember(
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
