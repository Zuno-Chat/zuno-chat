import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/calls/matrixrtc/call_unread_correction_provider.dart';
import '../../../core/errors/best_effort.dart';
import '../../../core/errors/connection_error.dart';
import '../../../core/format/member_count.dart';
import '../../../core/matrix/communities.dart';
import '../../../core/matrix/join_requests.dart';
import '../../../core/matrix/join_room.dart';
import '../../../core/matrix/local_username_dialog.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/optimistic_room_state.dart';
import '../../../core/matrix/room_access.dart';
import '../../../core/matrix/room_exit.dart';
import '../../../core/matrix/room_permission.dart';
import '../../../core/matrix/room_roles.dart';
import '../../../core/matrix/room_title.dart';
import '../../../core/ui/quick_action.dart';
import '../../../core/ui/route_settled.dart';
import '../../../core/ui/row_memo.dart';
import '../../../core/ui/section_label.dart';
import '../../chat/presentation/room_page.dart';
import '../../room_info/presentation/members_sheet.dart';
import '../../room_info/presentation/remove_member_dialog.dart';
import '../../room_info/presentation/role_picker.dart';
import '../../room_info/presentation/room_access_label.dart';
import '../../room_info/presentation/room_permissions_page.dart';
import '../../room_info/presentation/room_settings_page.dart';
import '../../room_info/presentation/room_topic.dart';
import '../../rooms/data/chat_row_data.dart';
import '../../rooms/presentation/chat_row.dart';
import '../../rooms/presentation/last_message_preview.dart';
import '../../rooms/presentation/new_room_dialog.dart';
import '../../rooms/presentation/room_kind_avatar.dart';

typedef CommunityRoomsLoader = Future<List<SpaceRoomsChunk$2>> Function(
  Room community,
);

typedef RoomOpener = void Function(BuildContext context, Room room);

Widget pageForRoom(Room room) =>
    room.isSpace ? CommunityPage(community: room) : RoomPage(room: room);

void _pushRoomPage(BuildContext context, Room room) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => RoomPage(room: room)));

enum _Menu { settings, permissions, leave }

enum _MemberAction {
  changeRole(Icons.badge_outlined, 'Change role'),
  remove(Icons.person_remove_outlined, 'Remove from community'),
  ban(Icons.block_outlined, 'Ban from community');

  final IconData icon;
  final String label;

  const _MemberAction(this.icon, this.label);
}

class CommunityPage extends ConsumerStatefulWidget {
  final Room community;
  final CommunityRoomsLoader loadRooms;
  final RoomOpener openRoom;

  const CommunityPage({
    required this.community,
    this.loadRooms = joinableCommunityRooms,
    this.openRoom = _pushRoomPage,
    super.key,
  });

  @override
  ConsumerState<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends ConsumerState<CommunityPage>
    with RouteSettled {
  final _memo = RowMemo<ChatRowData>();
  final _joining = <String>{};
  StreamSubscription<SyncUpdate>? _syncSub;
  List<SpaceRoomsChunk$2>? _more;
  bool _failed = false;
  bool _loadingMembers = false;

  Room get _community => widget.community;
  Client get _client => _community.client;

  @override
  void initState() {
    super.initState();
    _syncSub = _client.onSync.stream.listen(_onSync);
    if (_community.partial) unawaited(_loadFullState());
  }

  void _onSync(SyncUpdate update) {
    if (!mounted || !_concerns(update)) return;
    if (_community.membership != Membership.join) {
      _close();
      return;
    }
    setState(() {});
  }

  bool _concerns(SyncUpdate update) {
    if (update.accountData?.isNotEmpty ?? false) return true;
    final rooms = update.rooms;
    if (rooms == null) return false;
    final ids = {_community.id, ...communityChildIds(_community)};
    bool touches(Iterable<String>? changed) =>
        changed?.any(ids.contains) ?? false;
    return touches(rooms.join?.keys) ||
        touches(rooms.leave?.keys) ||
        touches(rooms.invite?.keys);
  }

  void _close() {
    if (ModalRoute.of(context)?.isCurrent ?? false) Navigator.of(context).pop();
  }

  Future<void> _loadFullState() async {
    await runBestEffort(_community.postLoad, label: 'community state');
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  @override
  void onRouteSettled() => unawaited(_loadMore());

  Future<void> _loadMore() async {
    setState(() => _failed = false);
    try {
      final rooms = await widget.loadRooms(_community);
      if (mounted) setState(() => _more = rooms);
    } catch (e) {
      logCaught('community rooms', e);
      if (mounted) setState(() => _failed = true);
    }
  }

  List<String> _viaFor(String roomId) {
    for (final child in _community.spaceChildren) {
      if (child.roomId == roomId) return child.via;
    }
    return [_client.userID!.domain!];
  }

  Future<void> _join(SpaceRoomsChunk$2 chunk) async {
    final id = chunk.roomId;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _joining.add(id));
    try {
      final room = await joinAndAwaitRoom(_client, id, via: _viaFor(id));
      if (room != null && mounted) widget.openRoom(context, room);
    } catch (e) {
      logCaught('join community room', e);
      messenger.showSnackBar(
        SnackBar(
          content: Text(failureMessage(e, failed: 'Could not join the room.')),
        ),
      );
    } finally {
      if (mounted) setState(() => _joining.remove(id));
    }
  }

  _Entry _entryFor(SpaceRoomsChunk$2 chunk, Set<String> asked) {
    if (chunk.joinRule != JoinRules.knock.text) return _Entry.join;
    if (asked.contains(chunk.roomId)) return _Entry.requested;
    return _Entry.ask;
  }

  Widget _joinable(SpaceRoomsChunk$2 chunk, Set<String> asked) {
    final id = chunk.roomId;
    final entry = _entryFor(chunk, asked);
    return _JoinableRoom(
      key: ValueKey(id),
      client: _client,
      chunk: chunk,
      entry: entry,
      busy: _joining.contains(id),
      onTap: () => switch (entry) {
        _Entry.join => _join(chunk),
        _Entry.ask => _answer(
          id,
          () =>
              ref.read(joinRequestsProvider.notifier).ask(id, via: _viaFor(id)),
          failed: 'Could not send the request.',
        ),
        _Entry.requested => _withdraw(id),
      },
    );
  }

  Future<void> _withdraw(String roomId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Withdraw your request?'),
        content: const Text('You can ask again later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _answer(
      roomId,
      () => ref.read(joinRequestsProvider.notifier).withdraw(roomId),
      failed: 'Could not withdraw the request.',
    );
  }

  Future<void> _answer(
    String roomId,
    Future<void> Function() action, {
    required String failed,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _joining.add(roomId));
    try {
      await action();
    } catch (e) {
      logCaught('join request', e);
      messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(e, failed: failed))),
      );
    } finally {
      if (mounted) setState(() => _joining.remove(roomId));
    }
  }

  Future<void> _invite() async {
    final userId = await showLocalUsernameDialog(
      context,
      client: _client,
      title: 'Invite to community',
      actionLabel: 'Invite',
    );
    if (userId == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _community.invite(userId);
      messenger.showSnackBar(const SnackBar(content: Text('Invitation sent')));
    } catch (e) {
      logCaught('invite to community', e);
      messenger.showSnackBar(
        const SnackBar(content: Text('Invitation not sent. Try again.')),
      );
    }
  }

  Future<void> _newRoom() async {
    final name = roomTitle(_community);
    final newRoom = await showNewRoomDialog(context, community: name);
    if (newRoom == null || newRoom.name.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    String roomId;
    try {
      roomId = await createCommunityRoom(
        _community,
        name: newRoom.name,
        access: newRoom.access,
      );
    } on RoomNotAddedToCommunity catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Room created, but not added to $name.')),
      );
      roomId = e.roomId;
    } catch (e) {
      logCaught('create community room', e);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            failureMessage(e, failed: 'Could not create the room.'),
          ),
        ),
      );
      return;
    }
    final room = _client.getRoomById(roomId);
    if (room != null && mounted) widget.openRoom(context, room);
  }

  Future<void> _openAndRefresh(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) setState(() {});
  }

  Future<void> _onMenu(_Menu choice) async {
    switch (choice) {
      case _Menu.settings:
        await _openAndRefresh(RoomSettingsPage(room: _community));
      case _Menu.permissions:
        await _openAndRefresh(RoomPermissionsPage(room: _community));
      case _Menu.leave:
        final left = await confirmAndExitRoom(context, _community);
        if (left && mounted) _close();
    }
  }

  Widget _roomRow(
    Room room,
    Map<String, int> corrections,
    DateTime now,
    bool use24Hour,
  ) {
    final data = chatRowDataFor(
      room,
      unreadCorrections: corrections,
      now: now,
      use24Hour: use24Hour,
    );
    return _memo.obtain(
      room.id,
      data,
      () => ChatRow(
        key: ValueKey(room.id),
        data: data,
        client: _client,
        preview: LastMessagePreview(room: room, event: room.lastEvent),
        onTap: () => widget.openRoom(context, room),
      ),
    );
  }

  Future<void> _viewMembers() async {
    if (_loadingMembers) return;
    _loadingMembers = true;
    final community = _community;
    const shown = [Membership.join, Membership.invite];
    List<User> people;
    try {
      people = await community.requestParticipants(shown);
    } catch (e) {
      logCaught('community members', e);
      people = community.getParticipants(shown);
    } finally {
      _loadingMembers = false;
    }
    if (!mounted) return;
    final user = await showMembersSheet(
      context,
      room: community,
      members: membersOwnerFirst(community, people),
      canManage: (user) => _memberActions(user).isNotEmpty,
    );
    if (user == null || !mounted) return;
    await _manageMember(user);
  }

  List<_MemberAction> _memberActions(User user) {
    final community = _community;
    if (user.membership != Membership.join) return const [];
    final manageable = canManageMember(community, user.id);
    return [
      if (assignableRolesFor(community, targetUserId: user.id).isNotEmpty)
        _MemberAction.changeRole,
      if (manageable && community.canKick) _MemberAction.remove,
      if (manageable && community.canBan) _MemberAction.ban,
    ];
  }

  Future<void> _manageMember(User user) async {
    final actions = _memberActions(user);
    final action = await showModalBottomSheet<_MemberAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            for (final action in actions)
              ListTile(
                leading: Icon(action.icon),
                title: Text(action.label),
                onTap: () => Navigator.of(context).pop(action),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _MemberAction.changeRole:
        await _changeRole(user);
      case _MemberAction.remove:
        await _removeMember(user, ban: false);
      case _MemberAction.ban:
        await _removeMember(user, ban: true);
    }
  }

  Future<void> _changeRole(User user) async {
    final community = _community;
    final current = roomRoleOfUser(community, user.id);
    final chosen = await showRolePicker(
      context,
      current: current,
      options: assignableRolesFor(community, targetUserId: user.id),
    );
    if (chosen == null || chosen == current || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await setUserRoomRole(community, user.id, chosen);
      if (mounted) setState(() {});
    } catch (e) {
      logCaught('change community role', e);
      messenger.showSnackBar(
        const SnackBar(content: Text('Role not changed. Try again.')),
      );
    }
  }

  Future<void> _removeMember(User user, {required bool ban}) async {
    final confirmed = await confirmRemoveMember(
      context,
      name: user.calcDisplayname(),
      ban: ban,
      place: 'community',
      note: 'They stay in rooms they already joined.',
    );
    if (!confirmed || !mounted) return;
    final community = _community;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await (ban ? community.ban(user.id) : community.kick(user.id));
      applyOptimisticRoomState(community, EventTypes.RoomMember, {
        ...?community.getState(EventTypes.RoomMember, user.id)?.content,
        'membership': (ban ? Membership.ban : Membership.leave).name,
      }, stateKey: user.id);
      if (mounted) setState(() {});
    } catch (e) {
      logCaught(ban ? 'ban from community' : 'remove from community', e);
      messenger.showSnackBar(
        SnackBar(
          content: Text('${ban ? 'Not banned' : 'Not removed'}. Try again.'),
        ),
      );
    }
  }

  bool get _canEditSettings =>
      _community.canChangeStateEvent(EventTypes.RoomName) ||
      _community.canChangeStateEvent(EventTypes.RoomTopic) ||
      _community.canChangeStateEvent(EventTypes.RoomAvatar) ||
      canChangeRoomAccess(_community);

  @override
  Widget build(BuildContext context) {
    final community = _community;
    final corrections = ref.watch(callUnreadCorrectionProvider);
    final rooms = communityRooms(community);
    _memo.retainOnly(rooms.map((room) => room.id));
    final joinable = _more
        ?.where(
          (c) => _client.getRoomById(c.roomId)?.membership != Membership.join,
        )
        .toList();
    final asked = ref.watch(joinRequestsProvider);
    final canInvite = community.canInvite;
    final canAddRooms = community.canChangeStateEvent(EventTypes.SpaceChild);
    final now = DateTime.now();
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      appBar: AppBar(
        actions: [
          PopupMenuButton<_Menu>(
            tooltip: 'More',
            onSelected: _onMenu,
            itemBuilder: (context) => [
              if (_canEditSettings)
                const PopupMenuItem(
                  value: _Menu.settings,
                  child: Text('Community settings'),
                ),
              if (roomPermissionsAccessFor(community) !=
                  RoomPermissionsAccess.hidden)
                const PopupMenuItem(
                  value: _Menu.permissions,
                  child: Text('Roles & permissions'),
                ),
              PopupMenuItem(
                value: _Menu.leave,
                child: Text(roomExitLabel(community)),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadMore,
        child: MediaQuery.removePadding(
          context: context,
          removeBottom: true,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(bottom: 24 + bottomInset),
            children: [
              _Header(community: community, onMembers: _viewMembers),
              if (canInvite || canAddRooms)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (canInvite)
                        Flexible(
                          child: QuickAction(
                            icon: Icons.person_add_alt_outlined,
                            label: 'Invite',
                            onTap: _invite,
                          ),
                        ),
                      if (canAddRooms)
                        Flexible(
                          child: QuickAction(
                            icon: Icons.add_comment_outlined,
                            label: 'New room',
                            onTap: _newRoom,
                          ),
                        ),
                    ],
                  ),
                ),
              if (rooms.isNotEmpty) ...[
                const SectionLabel('Your rooms'),
                for (final room in rooms)
                  _roomRow(room, corrections, now, use24Hour),
              ],
              if (_failed)
                _LoadFailed(onRetry: _loadMore)
              else if (joinable == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (joinable.isNotEmpty) ...[
                const SectionLabel('More rooms'),
                for (final chunk in joinable) _joinable(chunk, asked),
              ] else if (rooms.isEmpty)
                _NoRooms(canAddRooms: canAddRooms),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Room community;
  final VoidCallback onMembers;

  const _Header({required this.community, required this.onMembers});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = roomTitle(community);
    final topic = community.topic.trim();
    final members =
        community.summary.mJoinedMemberCount ??
        community.getParticipants([Membership.join]).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 18),
      child: Column(
        children: [
          MxcAvatar(
            client: community.client,
            avatarUrl: community.avatar,
            fallbackText: name,
            toneSeed: community.id,
            radius: 44,
            shape: AvatarShape.roundedSquare,
          ),
          const SizedBox(height: 12),
          Text(
            name,
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: RoomAccessLabel.of(community)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('•', style: theme.textTheme.bodySmall),
              ),
              Flexible(
                child: TextButton(
                  onPressed: onMembers,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: theme.textTheme.bodySmall,
                  ),
                  child: Text(
                    memberCountLabel(members),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          if (topic.isNotEmpty) ...[
            const SizedBox(height: 12),
            RoomTopic(topic: topic),
          ],
        ],
      ),
    );
  }
}

enum _Entry { join, ask, requested }

class _JoinableRoom extends StatelessWidget {
  final Client client;
  final SpaceRoomsChunk$2 chunk;
  final _Entry entry;
  final bool busy;
  final VoidCallback onTap;

  const _JoinableRoom({
    required this.client,
    required this.chunk,
    required this.entry,
    required this.busy,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final name = chunk.name?.trim();
    final title = name == null || name.isEmpty ? 'Unnamed room' : name;
    final topic = chunk.topic?.trim();
    final detail = [
      if (entry != _Entry.join) RoomAccess.askToJoin.label,
      memberCountLabel(chunk.numJoinedMembers),
      if (topic != null && topic.isNotEmpty) topic,
    ].join(' • ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
      child: Row(
        children: [
          RoomKindAvatar(
            client: client,
            avatarUrl: chunk.avatarUrl,
            fallbackText: title,
            isDirect: false,
            radius: ChatRow.avatarRadius,
            toneSeed: chunk.roomId,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (entry == _Entry.requested)
            OutlinedButton(
              onPressed: busy ? null : onTap,
              child: const Text('Requested'),
            )
          else
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.secondaryContainer,
                foregroundColor: colors.onSecondaryContainer,
              ),
              onPressed: busy ? null : onTap,
              child: Text(entry == _Entry.ask ? 'Ask' : 'Join'),
            ),
        ],
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  final VoidCallback onRetry;

  const _LoadFailed({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        children: [
          Text(
            'Could not load more rooms.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class _NoRooms extends StatelessWidget {
  final bool canAddRooms;

  const _NoRooms({required this.canAddRooms});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
      child: Column(
        children: [
          Text('No rooms here yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            canAddRooms
                ? 'Add the first one with New room.'
                : 'Rooms added to this community show here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
