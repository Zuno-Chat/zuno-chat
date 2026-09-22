import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

import '../../../core/calls/matrixrtc/call_member_state.dart';
import '../../../core/calls/models/call_kind.dart';
import '../../../core/errors/best_effort.dart';
import '../../../core/matrix/abuse_report.dart';
import '../../../core/matrix/local_username_dialog.dart';
import '../../../core/matrix/matrix_ids.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/room_access.dart';
import '../../../core/matrix/room_exit.dart';
import '../../../core/matrix/room_permission.dart';
import '../../../core/matrix/room_roles.dart';
import '../../../core/matrix/room_title.dart';
import '../../../core/security/security_emphasis.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/card_list_view.dart';
import '../../../core/ui/circle_icon.dart';
import '../../../core/ui/route_settled.dart';
import '../../../core/ui/zuno_theme.dart';
import '../../blocking/presentation/block_person.dart';
import '../../chat/presentation/room_page.dart';
import '../../reports/presentation/report_sheet.dart';
import 'member_tile.dart';
import 'members_sheet.dart';
import 'people_trust_tile.dart';
import 'role_picker.dart';
import 'room_access_label.dart';
import 'room_media_section.dart';
import 'room_permissions_page.dart';
import 'room_settings_page.dart';

enum _MemberAction { message, changeRole, remove, ban, block, report }

const _memberPreviewCount = 5;

enum RoomInfoResult { left }

class RoomInfoPage extends StatefulWidget {
  final Room room;
  final BlockPerson? blockPerson;
  final void Function(CallKind kind)? onStartCall;

  const RoomInfoPage({
    required this.room,
    this.blockPerson,
    this.onStartCall,
    super.key,
  });

  @override
  State<RoomInfoPage> createState() => _RoomInfoPageState();
}

class _RoomInfoPageState extends State<RoomInfoPage>
    with RouteSettled<RoomInfoPage> {
  bool? _mutedOverride;
  bool _muteBusy = false;
  Completer<void>? _pushRulesArrived;
  bool _membersFromMemory = false;
  List<User>? _participants;
  bool _loadingParticipants = true;
  StreamSubscription<void>? _roomStateSub;

  Future<void> _setMuted(bool muted) async {
    if (_muteBusy) return;
    final messenger = ScaffoldMessenger.of(context);
    final arrived = _pushRulesArrived = Completer<void>();
    final sub = widget.room.client.onSync.stream.listen((sync) {
      final rules =
          sync.accountData?.any((e) => e.type == 'm.push_rules') ?? false;
      if (rules && !arrived.isCompleted) arrived.complete();
    });
    setState(() {
      _muteBusy = true;
      _mutedOverride = muted;
    });
    var refused = false;
    var confirmed = false;
    try {
      await widget.room.setPushRuleState(
        muted ? PushRuleState.dontNotify : PushRuleState.notify,
      );
      await arrived.future.timeout(const Duration(seconds: 10));
      confirmed = true;
    } on TimeoutException {
      confirmed = false;
    } catch (e) {
      logCaught('mute from room info', e);
      refused = true;
    } finally {
      await sub.cancel();
    }
    if (!mounted) return;
    setState(() {
      _muteBusy = false;
      if (refused || confirmed) _mutedOverride = null;
    });
    if (refused) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            muted ? 'Not muted. Try again.' : 'Not unmuted. Try again.',
          ),
        ),
      );
    }
  }

  Future<void> _exit() async {
    final navigator = Navigator.of(context);
    if (!await confirmAndExitRoom(context, widget.room)) return;
    if (mounted) navigator.pop(RoomInfoResult.left);
  }

  @override
  void initState() {
    super.initState();
    _roomStateSub = widget.room.client.onRoomState.stream.listen((update) {
      if (update.roomId == widget.room.id && mounted) setState(() {});
    });
  }

  @override
  void onRouteSettled() {
    unawaited(runBestEffort(_loadParticipants, label: 'loadParticipants'));
  }

  @override
  void dispose() {
    final arrived = _pushRulesArrived;
    if (arrived != null && !arrived.isCompleted) arrived.complete();
    _roomStateSub?.cancel();
    super.dispose();
  }

  List<User> _byName(List<User> users) => users
    ..sort(
      (a, b) => a.calcDisplayname().toLowerCase().compareTo(
        b.calcDisplayname().toLowerCase(),
      ),
    );

  Future<void> _loadParticipants() async {
    setState(() => _loadingParticipants = true);
    try {
      final participants = await widget.room.requestParticipants();
      if (mounted) {
        setState(() {
          _participants = _byName(participants);
          _membersFromMemory = false;
        });
      }
    } catch (e) {
      logCaught('load members', e);
      if (mounted && _participants == null) {
        setState(() {
          _participants = _byName(widget.room.getParticipants());
          _membersFromMemory = true;
        });
      }
    } finally {
      if (mounted) setState(() => _loadingParticipants = false);
    }
  }

  Future<void> _invite() async {
    final client = widget.room.client;
    final userId = await showLocalUsernameDialog(
      context,
      client: client,
      title: 'Invite to room',
      actionLabel: 'Invite',
    );
    if (userId == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.room.invite(userId);
      messenger.showSnackBar(const SnackBar(content: Text('Invitation sent')));
      await _loadParticipants();
    } catch (e) {
      logCaught('invite', e);
      messenger.showSnackBar(
        const SnackBar(content: Text('Invitation not sent. Try again.')),
      );
    }
  }

  Future<void> _changeMemberRole(User user) async {
    final room = widget.room;
    final options = assignableRolesFor(room, targetUserId: user.id);
    final current = roomRoleOfUser(room, user.id);
    final chosen = await showRolePicker(
      context,
      current: current,
      options: options,
    );
    if (chosen == null || chosen == current || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await setUserRoomRole(room, user.id, chosen);
      if (mounted) setState(() {});
    } catch (e) {
      logCaught('change role', e);
      messenger.showSnackBar(
        const SnackBar(content: Text('Role not changed. Try again.')),
      );
    }
  }

  bool _canManage(User user) =>
      !widget.room.isDirectChat &&
      user.membership != Membership.invite &&
      user.id != widget.room.client.userID;

  Future<void> _viewAllMembers() async {
    final room = widget.room;
    final user = await showMembersSheet(
      context,
      room: room,
      members: membersOwnerFirst(room, _participants ?? const []),
      canManage: _canManage,
    );
    if (user == null || !mounted) return;
    await _manageMember(user);
  }

  Future<void> _manageMember(User user) async {
    final room = widget.room;
    final canChangeRole = assignableRolesFor(
      room,
      targetUserId: user.id,
    ).isNotEmpty;
    final manageable = canManageMember(room, user.id);
    final canRemove = manageable && room.canKick;
    final canBanUser = manageable && room.canBan;

    final action = await showModalBottomSheet<_MemberAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('Start a chat'),
              onTap: () => Navigator.of(context).pop(_MemberAction.message),
            ),
            if (canChangeRole)
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('Change role'),
                onTap: () =>
                    Navigator.of(context).pop(_MemberAction.changeRole),
              ),
            if (canRemove)
              ListTile(
                leading: const Icon(Icons.person_remove_outlined),
                title: const Text('Remove from room'),
                onTap: () => Navigator.of(context).pop(_MemberAction.remove),
              ),
            if (canBanUser)
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: const Text('Ban from room'),
                onTap: () => Navigator.of(context).pop(_MemberAction.ban),
              ),
            if (canBlockPerson(user.id))
              ListTile(
                leading: const Icon(Icons.do_not_disturb_on_outlined),
                title: const Text('Block'),
                onTap: () => Navigator.of(context).pop(_MemberAction.block),
              ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Report'),
              onTap: () => Navigator.of(context).pop(_MemberAction.report),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    switch (action) {
      case _MemberAction.message:
        await _messageMember(user);
      case _MemberAction.changeRole:
        await _changeMemberRole(user);
      case _MemberAction.remove:
        await _removeMember(user, ban: false);
      case _MemberAction.ban:
        await _removeMember(user, ban: true);
      case _MemberAction.block:
        await _blockPerson(user.id, user.calcDisplayname());
      case _MemberAction.report:
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
      block: widget.blockPerson,
    );
    if (blocked) navigator.popUntil((route) => route.isFirst);
  }

  Future<void> _reportPerson(String userId, String name) async {
    final room = widget.room;
    final messenger = ScaffoldMessenger.of(context);
    final sent = await showReportSheet(
      context,
      title: 'Report $name',
      explanation: room.isDirectChat
          ? 'The report goes to Zuno and names this person. Zuno cannot read '
                'your messages, so describe what happened.'
          : 'The report goes to Zuno and names this person. Room admins can '
                'remove people from this room. A report is for what they '
                'cannot fix.',
      onSend: (reason, note) => reportPerson(
        room.client,
        userId,
        reason,
        note: note,
        roomId: room.id,
      ),
    );
    if (sent) {
      messenger.showSnackBar(const SnackBar(content: Text('Report sent')));
    }
  }

  Future<void> _messageMember(User user) async {
    final client = widget.room.client;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final roomId = await client.startDirectChat(
        user.id,
        enableEncryption: true,
      );
      final room = client.getRoomById(roomId);
      if (room != null && mounted) {
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => RoomPage(room: room)));
      }
    } catch (e) {
      logCaught('start chat', e);
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not start the chat. Try again.')),
      );
    }
  }

  Future<void> _removeMember(User user, {required bool ban}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          ban
              ? 'Ban ${user.calcDisplayname()}?'
              : 'Remove ${user.calcDisplayname()}?',
        ),
        content: Text(
          ban
              ? 'They are removed from the room and cannot rejoin unless '
                    'unbanned.'
              : 'They are removed from the room and can rejoin if invited '
                    'again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(ban ? 'Ban' : 'Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await (ban ? widget.room.ban(user.id) : widget.room.kick(user.id));
      await _loadParticipants();
      if (mounted) setState(() {});
    } catch (e) {
      logCaught(ban ? 'ban member' : 'remove member', e);
      final failure = ban ? 'Not banned' : 'Not removed';
      messenger.showSnackBar(SnackBar(content: Text('$failure. Try again.')));
    }
  }

  Future<void> _unbanMember(String userId) async {
    if (!canManageMember(widget.room, userId)) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.room.unban(userId);
      if (mounted) setState(() {});
    } catch (e) {
      logCaught('unban', e);
      messenger.showSnackBar(
        const SnackBar(content: Text('Not unbanned. Try again.')),
      );
    }
  }

  Widget _bannedMemberTile(Room room, String userId) {
    final user = room.unsafeGetUserFromMemoryOrFallback(userId);
    return ListTile(
      leading: MxcAvatar(
        client: room.client,
        avatarUrl: user.avatarUrl,
        fallbackText: user.calcDisplayname(),
        radius: 18,
      ),
      title: Text(user.calcDisplayname()),
      subtitle: Text(withoutServer(userId)),
      trailing: canManageMember(room, userId)
          ? TextButton(
              onPressed: () => _unbanMember(userId),
              child: const Text('Unban'),
            )
          : null,
    );
  }

  Future<void> _enableEncryption() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enable encryption?'),
        actionsOverflowDirection: VerticalDirection.up,
        actionsOverflowButtonSpacing: 4,
        content: const Text(
          'Messages sent from now on are end-to-end encrypted. Nobody can turn '
          'it off again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Enable encryption'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.room.enableEncryption();
      if (mounted) setState(() {});
    } catch (e) {
      logCaught('enable encryption', e);
      messenger.showSnackBar(
        const SnackBar(content: Text('Encryption not enabled. Try again.')),
      );
    }
  }

  String _membersTitle(Room room, List<User>? participants) {
    if (participants == null) return 'Members';
    final count = _membersFromMemory
        ? _summaryMemberCount(room, participants.length)
        : participants.length;
    return 'Members ($count)';
  }

  void _copyToClipboard(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$label copied')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final room = widget.room;
    final name = roomTitle(room);
    final participants = _participants;
    final members = membersOwnerFirst(room, participants ?? const <User>[]);
    final canonicalAlias = room.canonicalAlias;
    final chatPartnerId = room.directChatMatrixID;
    final permissionsAccess = roomPermissionsAccessFor(room);
    final canSeePermissions =
        !room.isDirectChat && permissionsAccess != RoomPermissionsAccess.hidden;
    final canEditAnyRoomSetting =
        !room.isDirectChat &&
        (room.canChangeStateEvent(EventTypes.RoomName) ||
            room.canChangeStateEvent(EventTypes.RoomTopic) ||
            room.canChangeStateEvent(EventTypes.RoomCanonicalAlias) ||
            room.canChangeHistoryVisibility ||
            room.canChangeStateEvent(EventTypes.RoomAvatar) ||
            canChangeRoomAccess(room));

    final onStartCall = widget.onStartCall;
    final canCall =
        onStartCall != null &&
        canPublishCallMemberState(room) &&
        hasSomeoneToCall(room);
    final muted =
        _mutedOverride ?? room.pushRuleState == PushRuleState.dontNotify;
    final showSecurity =
        room.isDirectChat &&
        (!room.encrypted ||
            participants == null ||
            participants.any((u) => u.id != room.client.userID));
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(room.isDirectChat ? 'Chat info' : 'Room info'),
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            runBestEffort(_loadParticipants, label: 'loadParticipants'),
        child: CardListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 18),
              child: Column(
                children: [
                  MxcAvatar(
                    client: room.client,
                    avatarUrl: room.avatar,
                    fallbackText: name,
                    toneSeed: chatPartnerId ?? room.id,
                    radius: 44,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    name,
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  if (room.encrypted || !room.isDirectChat) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (room.encrypted) ...[
                          Icon(
                            Icons.lock_outline,
                            size: 16,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text('Encrypted', style: theme.textTheme.bodySmall),
                        ],
                        if (room.encrypted && !room.isDirectChat)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              '\u2022',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        if (!room.isDirectChat)
                          RoomAccessLabel(access: roomAccessOf(room)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (canCall) ...[
                    _QuickAction(
                      icon: Icons.call_outlined,
                      label: 'Call',
                      tooltip: 'Voice call',
                      onTap: () => onStartCall(CallKind.voice),
                    ),
                    _QuickAction(
                      icon: Icons.videocam_outlined,
                      label: 'Video',
                      tooltip: 'Video call',
                      onTap: () => onStartCall(CallKind.video),
                    ),
                  ],
                  _QuickAction(
                    icon: muted
                        ? Icons.notifications_outlined
                        : Icons.notifications_off_outlined,
                    label: muted ? 'Unmute' : 'Mute',
                    onTap: () => _setMuted(!muted),
                  ),
                  if (!room.isDirectChat && room.canInvite)
                    _QuickAction(
                      icon: Icons.person_add_alt_outlined,
                      label: 'Invite',
                      onTap: _invite,
                    ),
                ],
              ),
            ),
            if (canEditAnyRoomSetting || canSeePermissions)
              CardGroup(
                children: [
                  if (canEditAnyRoomSetting)
                    ListTile(
                      leading: const CircleIcon(Icons.edit_outlined),
                      title: const Text('Room settings'),
                      subtitle: const Text('Name, topic, photo'),
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
                      title: const Text('Roles & permissions'),
                      subtitle: Text(
                        permissionsAccess == RoomPermissionsAccess.readOnly
                            ? 'View only'
                            : 'Who can do what',
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
                title: 'Security',
                children: [
                  if (!room.encrypted)
                    ListTile(
                      dense: true,
                      leading: Icon(notEncryptedIcon, color: colors.error),
                      title: const Text('Not encrypted'),
                      subtitle: const Text(
                        'Messages in this chat reach the server unencrypted',
                      ),
                    ),
                  if (room.encrypted)
                    PeopleTrustTile(room: room, participants: participants)
                  else if (room.canChangeStateEvent(EventTypes.Encryption))
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.enhanced_encryption_outlined),
                      title: const Text('Enable encryption'),
                      subtitle: const Text('Cannot be turned off again'),
                      onTap: _enableEncryption,
                    ),
                ],
              ),
            RoomMediaSection(room: room),
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
                          child: const Text('View all members'),
                        ),
                      ),
                  ],
                ],
              ),
            if (room.canBan && bannedUserIds(room).isNotEmpty)
              CardGroup(
                title: 'Banned',
                children: [
                  for (final userId in bannedUserIds(room))
                    _bannedMemberTile(room, userId),
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
                      title: Text('Block $name'),
                      onTap: () => _blockPerson(chatPartnerId, name),
                    ),
                  ListTile(
                    leading: const CircleIcon(Icons.flag_outlined),
                    title: Text('Report $name'),
                    onTap: () => _reportPerson(chatPartnerId, name),
                  ),
                ],
                ListTile(
                  leading: CircleIcon(roomExitIcon(room), danger: true),
                  title: Text(
                    roomExitLabel(room),
                    style: TextStyle(color: colors.error),
                  ),
                  onTap: _exit,
                ),
              ],
            ),
            if (canSeeAdvancedRoomInfo(room))
              CardGroup(
                title: 'Advanced',
                children: [
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.tag_outlined),
                    title: const Text('Room ID'),
                    subtitle: Text(withoutServer(room.id)),
                    trailing: const Icon(Icons.copy_outlined, size: 18),
                    onTap: () =>
                        _copyToClipboard('Room ID', withoutServer(room.id)),
                  ),
                  if (canonicalAlias.isNotEmpty)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.alternate_email_outlined),
                      title: const Text('Room alias'),
                      subtitle: Text(withoutServer(canonicalAlias)),
                      trailing: const Icon(Icons.copy_outlined, size: 18),
                      onTap: () => _copyToClipboard(
                        'Room alias',
                        withoutServer(canonicalAlias),
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

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? tooltip;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final action = Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(ZunoRadius.medium),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 52,
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: colors.onSecondaryContainer),
                ),
              ),
              const SizedBox(height: 6),
              Text(label, style: theme.textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
    final tooltip = this.tooltip;
    return tooltip == null ? action : Tooltip(message: tooltip, child: action);
  }
}
