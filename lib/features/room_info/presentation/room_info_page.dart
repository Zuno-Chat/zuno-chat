import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/calls/end_call.dart';
import '../../../core/calls/matrixrtc/call_member_state.dart';
import '../../../core/calls/models/call_kind.dart';
import '../../../core/errors/best_effort.dart';
import '../../../core/errors/caught_errors.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/abuse_report.dart';
import '../../../core/matrix/matrix_ids.dart';
import '../../../core/matrix/optimistic_room_state.dart';
import '../../../core/matrix/room_access.dart';
import '../../../core/matrix/room_changes.dart';
import '../../../core/matrix/room_exit.dart';
import '../../../core/matrix/room_invite.dart';
import '../../../core/matrix/room_mute.dart';
import '../../../core/matrix/room_permission.dart';
import '../../../core/matrix/room_roles.dart';
import '../../../core/matrix/room_title.dart';
import '../../../core/security/security_emphasis.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';
import '../../../core/ui/circle_icon.dart';
import '../../../core/ui/confirm_dialog.dart';
import '../../../core/ui/danger_tile.dart';
import '../../../core/ui/notice.dart';
import '../../../core/ui/quick_action.dart';
import '../../../core/ui/route_settled.dart';
import '../../blocking/presentation/block_person.dart';
import '../../chat/presentation/media_viewer/media_viewer_page.dart';
import '../../chat/presentation/room_page.dart';
import '../../communities/presentation/join_requests_view.dart';
import '../../reports/presentation/report_sheet.dart';
import 'member_actions.dart';
import 'member_tile.dart';
import 'members_sheet.dart';
import 'people_trust_tile.dart';
import 'room_access_label.dart';
import 'room_header.dart';
import 'room_media_section.dart';
import 'room_permissions_page.dart';
import 'room_settings_page.dart';

const _memberPreviewCount = 5;

enum RoomInfoResult { left }

class RoomInfoPage extends ConsumerStatefulWidget {
  final Room room;
  final ViewerChat viewerChat;
  final BlockPerson? blockPerson;
  final void Function(CallKind kind)? onStartCall;

  const RoomInfoPage({
    required this.room,
    required this.viewerChat,
    this.blockPerson,
    this.onStartCall,
    super.key,
  });

  @override
  ConsumerState<RoomInfoPage> createState() => _RoomInfoPageState();
}

class _RoomInfoPageState extends ConsumerState<RoomInfoPage>
    with RouteSettled<RoomInfoPage> {
  bool _membersFromMemory = false;
  List<User>? _participants;
  bool _loadingParticipants = true;

  Future<void> _setMuted(bool muted) async {
    final asked = askToMuteRoom(context, widget.room, muted);
    setState(() {});
    await asked;
    if (mounted) setState(() {});
  }

  Future<void> _exit() async {
    final navigator = Navigator.of(context);
    if (!await confirmAndExitRoom(
      context,
      widget.room,
      endCallsIn: ref.read(endCallsInProvider),
    )) {
      return;
    }
    if (mounted) navigator.pop(RoomInfoResult.left);
  }

  @override
  void onRouteSettled() {
    unawaited(runBestEffort(_loadParticipants, label: 'loadParticipants'));
  }

  List<User> _ordered(Iterable<User> users) {
    final names = {
      for (final user in users) user.id: user.calcDisplayname().toLowerCase(),
    };
    final byName = [...users]
      ..sort((a, b) => names[a.id]!.compareTo(names[b.id]!));
    return membersOwnerFirst(widget.room, byName);
  }

  Future<void> _loadParticipants() async {
    setState(() => _loadingParticipants = true);
    try {
      final participants = await widget.room.requestParticipants(const [
        Membership.join,
        Membership.invite,
      ]);
      if (mounted) {
        setState(() {
          _participants = _ordered(participants);
          _membersFromMemory = false;
        });
      }
    } catch (e, s) {
      reportCaught('load members', e, s);
      if (mounted && _participants == null) {
        setState(() {
          _participants = _ordered(widget.room.getParticipants());
          _membersFromMemory = true;
        });
      }
    } finally {
      if (mounted) setState(() => _loadingParticipants = false);
    }
  }

  Future<void> _invite() async {
    final invited = await inviteFromDialog(
      context,
      widget.room,
      title: context.l10n.roomInfoInviteToRoom,
    );
    if (invited != null) _listMembership(invited, Membership.invite);
  }

  void _listMembership(String userId, Membership membership) {
    final participants = _participants;
    if (!mounted || participants == null) return;
    setState(() {
      _participants = _ordered([
        for (final user in participants)
          if (user.id != userId) user,
        if (membership == Membership.invite)
          widget.room.unsafeGetUserFromMemoryOrFallback(userId),
      ]);
    });
  }

  bool _canManage(User user) => memberActionsFor(widget.room, user).isNotEmpty;

  Future<void> _viewAllMembers() async {
    final user = await showMembersSheet(
      context,
      room: widget.room,
      members: _participants ?? const [],
      canManage: _canManage,
    );
    if (user == null || !mounted) return;
    await _manageMember(user);
  }

  Future<void> _manageMember(User user) async {
    final room = widget.room;
    final action = await chooseMemberAction(context, room, user);
    if (action == null || !mounted) return;

    switch (action) {
      case MemberAction.message:
        await _messageMember(user);
      case MemberAction.changeRole:
        if (await changeMemberRole(context, room, user) && mounted) {
          setState(() {});
        }
      case MemberAction.remove || MemberAction.ban:
        final ban = action == MemberAction.ban;
        if (await removeMember(context, room, user, ban: ban)) {
          _listMembership(user.id, ban ? Membership.ban : Membership.leave);
        }
      case MemberAction.block:
        await _blockPerson(user.id, user.calcDisplayname());
      case MemberAction.report:
        await _reportPerson(user.id, user.calcDisplayname());
    }
  }

  Future<void> _blockPerson(String userId, String name) async {
    final navigator = Navigator.of(context);
    final blocked = await confirmAndBlockPerson(
      context,
      client: widget.room.client,
      userId: userId,
      name: name,
      endCallsIn: ref.read(endCallsInProvider),
      block: widget.blockPerson,
    );
    if (blocked) navigator.popUntil((route) => route.isFirst);
  }

  Future<void> _reportPerson(String userId, String name) async {
    final room = widget.room;
    final l10n = context.l10n;
    await showReportSheet(
      context,
      title: l10n.roomInfoReportPerson(name),
      explanation: room.isDirectChat
          ? l10n.roomInfoReportExplainDirect
          : l10n.roomInfoReportExplainGroup,
      onSend: (reason, note) => reportPerson(
        room.client,
        userId,
        reason,
        note: note,
        roomId: room.id,
      ),
    );
  }

  Future<void> _messageMember(User user) async {
    final client = widget.room.client;
    final navigator = Navigator.of(context);
    String? roomId;
    final started = await attempt(
      context,
      () async => roomId = await startEncryptedDirectChat(client, user.id),
      label: 'start chat',
      failed: context.l10n.roomsCouldNotStartChat,
    );
    final room = started ? client.getRoomById(roomId!) : null;
    if (room == null || !mounted) return;
    navigator.push(MaterialPageRoute(builder: (_) => RoomPage(room: room)));
  }

  Future<void> _unbanMember(String userId) async {
    final room = widget.room;
    if (!canManageMember(room, userId)) return;
    final unbanned = await attempt(
      context,
      () async {
        await room.unban(userId);
        applyOptimisticMembership(room, userId, Membership.leave);
      },
      label: 'unban',
      failed: context.l10n.roomInfoNotUnbanned,
    );
    if (unbanned) _listMembership(userId, Membership.leave);
  }

  Future<void> _enableEncryption() async {
    final l10n = context.l10n;
    final confirmed = await confirm(
      context,
      title: l10n.roomInfoEnableEncryptionTitle,
      body: l10n.roomInfoEnableEncryptionBody,
      confirmLabel: l10n.roomInfoEnableEncryption,
    );
    if (!confirmed || !mounted) return;

    final room = widget.room;
    await attempt(
      context,
      () async {
        await room.enableEncryption();
        applyOptimisticRoomState(room, EventTypes.Encryption, {
          'algorithm': Client.supportedGroupEncryptionAlgorithms.first,
        });
      },
      label: 'enable encryption',
      failed: l10n.roomInfoEncryptionNotEnabled,
    );
  }

  String _membersTitle(Room room, List<User>? participants) {
    if (participants == null) return context.l10n.roomInfoMembers;
    final count = _membersFromMemory
        ? _summaryMemberCount(room, participants.length)
        : participants.length;
    return context.l10n.roomInfoMembersCount(count);
  }

  @override
  Widget build(BuildContext context) => RoomChangesBuilder(
    changes: RoomChanges.state(widget.room),
    builder: _page,
  );

  Widget _page(BuildContext context) {
    final l10n = context.l10n;
    final room = widget.room;
    final name = roomTitle(room, l10n);
    final participants = _participants;
    final members = participants ?? const <User>[];
    final canonicalAlias = room.canonicalAlias;
    final chatPartnerId = room.directChatMatrixID;
    final permissionsAccess = roomPermissionsAccessFor(room);
    final canSeePermissions =
        !room.isDirectChat && permissionsAccess != RoomPermissionsAccess.hidden;
    final canEditSettings = canEditRoomSettings(room);
    final onStartCall = widget.onStartCall;
    final canCall = onStartCall != null && canStartCall(room);
    final muted = isRoomMuted(room);
    final showSecurity =
        room.isDirectChat &&
        (!room.encrypted ||
            participants == null ||
            participants.any((u) => u.id != room.client.userID));
    final banned = room.canBan ? bannedUserIds(room) : const <String>[];
    final messenger = ScaffoldMessenger.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          room.isDirectChat ? l10n.roomInfoChatInfo : l10n.roomInfoRoomInfo,
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            runBestEffort(_loadParticipants, label: 'loadParticipants'),
        child: CardListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            RoomHeader(
              room: room,
              details: [
                if (room.encrypted) const _EncryptedLabel(),
                if (!room.isDirectChat) RoomAccessLabel.of(room, l10n),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (canCall) ...[
                    Flexible(
                      child: QuickAction(
                        icon: Icons.call_outlined,
                        label: l10n.callsStartCall,
                        tooltip: l10n.callsStartVoiceCall,
                        onTap: () => onStartCall(CallKind.voice),
                      ),
                    ),
                    Flexible(
                      child: QuickAction(
                        icon: Icons.videocam_outlined,
                        label: l10n.roomInfoVideo,
                        tooltip: l10n.callsStartVideoCall,
                        onTap: () => onStartCall(CallKind.video),
                      ),
                    ),
                  ],
                  Flexible(
                    child: QuickAction(
                      icon: muted
                          ? Icons.notifications_outlined
                          : Icons.notifications_off_outlined,
                      label: muted ? l10n.roomsUnmute : l10n.roomsMute,
                      onTap: () => _setMuted(!muted),
                    ),
                  ),
                  if (!room.isDirectChat && room.canInvite)
                    Flexible(
                      child: QuickAction(
                        icon: Icons.person_add_alt_outlined,
                        label: l10n.commonInvite,
                        onTap: _invite,
                      ),
                    ),
                ],
              ),
            ),
            if (canEditSettings || canSeePermissions)
              CardGroup(
                children: [
                  if (canEditSettings)
                    ListTile(
                      leading: const CircleIcon(Icons.edit_outlined),
                      title: Text(l10n.roomInfoRoomSettings),
                      subtitle: Text(l10n.roomInfoRoomSettingsHint),
                      trailing: const Icon(Icons.chevron_right_outlined),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RoomSettingsPage(room: room),
                        ),
                      ),
                    ),
                  if (canSeePermissions)
                    ListTile(
                      leading: const CircleIcon(
                        Icons.admin_panel_settings_outlined,
                      ),
                      title: Text(l10n.roomInfoRolesAndPermissions),
                      subtitle: Text(
                        permissionsAccess == RoomPermissionsAccess.readOnly
                            ? l10n.roomInfoViewOnly
                            : l10n.roomInfoWhoCanDoWhat,
                      ),
                      trailing: const Icon(Icons.chevron_right_outlined),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RoomPermissionsPage(room: room),
                        ),
                      ),
                    ),
                ],
              ),
            if (showSecurity)
              CardGroup(
                title: l10n.roomInfoSecurity,
                children: [
                  if (!room.encrypted)
                    ListTile(
                      dense: true,
                      leading: const ExcludeSemantics(
                        child: NotEncryptedMark(),
                      ),
                      title: Text(l10n.roomInfoNotEncrypted),
                      subtitle: Text(l10n.roomInfoNotEncryptedHint),
                    ),
                  if (room.encrypted)
                    PeopleTrustTile(room: room, participants: participants)
                  else if (room.canChangeStateEvent(EventTypes.Encryption))
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.enhanced_encryption_outlined),
                      title: Text(l10n.roomInfoEnableEncryption),
                      subtitle: Text(l10n.roomInfoCannotTurnOff),
                      onTap: _enableEncryption,
                    ),
                ],
              ),
            RoomMediaSection(viewerChat: widget.viewerChat),
            JoinRequestsSection(room: room),
            if (!room.isDirectChat)
              CardGroup(
                title: _membersTitle(room, participants),
                children: [
                  if (_loadingParticipants)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    for (final user in members.take(_memberPreviewCount))
                      MemberTile(
                        room: room,
                        user: user,
                        onTap: _canManage(user)
                            ? () => _manageMember(user)
                            : null,
                      ),
                    if (members.length > _memberPreviewCount)
                      Center(
                        child: TextButton(
                          onPressed: _viewAllMembers,
                          child: Text(l10n.roomInfoViewAllMembers),
                        ),
                      ),
                  ],
                ],
              ),
            if (banned.isNotEmpty)
              CardGroup(
                title: l10n.roomInfoBanned,
                children: [
                  for (final userId in banned)
                    MemberTile(
                      room: room,
                      user: room.unsafeGetUserFromMemoryOrFallback(userId),
                      trailing: canManageMember(room, userId)
                          ? TextButton(
                              onPressed: () => _unbanMember(userId),
                              child: Text(l10n.roomInfoUnban),
                            )
                          : null,
                    ),
                ],
              ),
            CardGroup(
              children: [
                if (chatPartnerId != null) ...[
                  if (canBlockPerson(chatPartnerId))
                    ListTile(
                      leading: const CircleIcon(
                        Icons.do_not_disturb_on_outlined,
                      ),
                      title: Text(l10n.roomInfoBlockPerson(name)),
                      onTap: () => _blockPerson(chatPartnerId, name),
                    ),
                  ListTile(
                    leading: const CircleIcon(Icons.flag_outlined),
                    title: Text(l10n.roomInfoReportPerson(name)),
                    onTap: () => _reportPerson(chatPartnerId, name),
                  ),
                ],
                DangerTile(
                  icon: roomExitIcon(room),
                  label: roomExitLabel(room, l10n),
                  onTap: _exit,
                ),
              ],
            ),
            if (canSeeAdvancedRoomInfo(room))
              CardGroup(
                title: l10n.roomInfoAdvanced,
                children: [
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.tag_outlined),
                    title: Text(l10n.roomInfoRoomId),
                    subtitle: Text(withoutServer(room.id)),
                    trailing: const Icon(Icons.copy_outlined, size: 18),
                    onTap: () => messenger.copy(
                      room.id,
                      copied: l10n.roomInfoRoomIdCopied,
                    ),
                  ),
                  if (canonicalAlias.isNotEmpty)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.alternate_email_outlined),
                      title: Text(l10n.roomInfoRoomAlias),
                      subtitle: Text(withoutServer(canonicalAlias)),
                      trailing: const Icon(Icons.copy_outlined, size: 18),
                      onTap: () => messenger.copy(
                        canonicalAlias,
                        copied: l10n.roomInfoRoomAliasCopied,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

int _summaryMemberCount(Room room, int known) {
  final joined = room.summary.mJoinedMemberCount ?? 0;
  final invited = room.summary.mInvitedMemberCount ?? 0;
  final summary = joined + invited;
  return summary > known ? summary : known;
}

class _EncryptedLabel extends StatelessWidget {
  const _EncryptedLabel();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.lock_outline,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            context.l10n.roomInfoEncrypted,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
