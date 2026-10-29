import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/calls/end_call.dart';
import '../../../core/calls/matrixrtc/call_unread_correction_provider.dart';
import '../../../core/errors/best_effort.dart';
import '../../../core/errors/caught_errors.dart';
import '../../../core/format/date_labels.dart';
import '../../../core/format/human_units.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/communities.dart';
import '../../../core/matrix/join_requests.dart';
import '../../../core/matrix/join_room.dart';
import '../../../core/matrix/room_access.dart';
import '../../../core/matrix/room_changes.dart';
import '../../../core/matrix/room_exit.dart';
import '../../../core/matrix/room_invite.dart';
import '../../../core/matrix/room_permission.dart';
import '../../../core/matrix/room_roles.dart';
import '../../../core/matrix/room_title.dart';
import '../../../core/ui/confirm_dialog.dart';
import '../../../core/ui/failure_notice.dart';
import '../../../core/ui/notice.dart';
import '../../../core/ui/quick_action.dart';
import '../../../core/ui/route_settled.dart';
import '../../../core/ui/row_memo.dart';
import '../../../core/ui/section_label.dart';
import '../../chat/presentation/room_page.dart';
import '../../room_info/presentation/member_actions.dart';
import '../../room_info/presentation/members_sheet.dart';
import '../../room_info/presentation/room_access_label.dart';
import '../../room_info/presentation/room_header.dart';
import '../../room_info/presentation/room_permissions_page.dart';
import '../../room_info/presentation/room_settings_page.dart';
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
  List<SpaceRoomsChunk$2>? _more;
  bool _failed = false;
  bool _loadingMembers = false;

  Room get _community => widget.community;
  Client get _client => _community.client;

  @override
  void initState() {
    super.initState();
    if (_community.partial) unawaited(_loadFullState());
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

  void _closeIfLeft() {
    if (_community.membership != Membership.join) _close();
  }

  void _close() {
    if (ModalRoute.of(context)?.isCurrent ?? false) Navigator.of(context).pop();
  }

  Future<void> _loadFullState() async {
    await runBestEffort(_community.postLoad, label: 'community state');
    if (mounted) setState(() {});
  }

  @override
  void onRouteSettled() => unawaited(_loadMore());

  Future<void> _loadMore() async {
    setState(() => _failed = false);
    try {
      final rooms = await widget.loadRooms(_community);
      if (mounted) setState(() => _more = rooms);
    } catch (e, s) {
      reportCaught('community rooms', e, s);
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
    setState(() => _joining.add(id));
    Room? room;
    await attempt(
      context,
      () async => room = await joinAndAwaitRoom(_client, id, via: _viaFor(id)),
      label: 'join community room',
      failed: context.l10n.roomsCouldNotJoinRoom,
    );
    if (!mounted) return;
    setState(() => _joining.remove(id));
    final joined = room;
    if (joined != null) widget.openRoom(context, joined);
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
          failed: context.l10n.communitiesRequestFailed,
        ),
        _Entry.requested => _withdraw(id),
      },
    );
  }

  Future<void> _withdraw(String roomId) async {
    final l10n = context.l10n;
    final confirmed = await confirm(
      context,
      title: l10n.communitiesWithdrawTitle,
      body: l10n.communitiesWithdrawBody,
      confirmLabel: l10n.communitiesWithdraw,
    );
    if (!confirmed || !mounted) return;
    await _answer(
      roomId,
      () => ref.read(joinRequestsProvider.notifier).withdraw(roomId),
      failed: l10n.communitiesWithdrawFailed,
    );
  }

  Future<void> _answer(
    String roomId,
    Future<void> Function() action, {
    required String failed,
  }) async {
    setState(() => _joining.add(roomId));
    await attempt(context, action, label: 'join request', failed: failed);
    if (mounted) setState(() => _joining.remove(roomId));
  }

  Future<void> _invite() => inviteFromDialog(
    context,
    _community,
    title: context.l10n.communitiesInviteTitle,
  );

  Future<void> _newRoom() async {
    final l10n = context.l10n;
    final name = roomTitle(_community, l10n);
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
      messenger.say(l10n.communitiesRoomNotAdded(name));
      roomId = e.roomId;
    } catch (e, s) {
      reportCaught('create community room', e, s);
      messenger.sayFailed(l10n, e, failed: l10n.roomsCouldNotCreateRoom);
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
        final left = await confirmAndExitRoom(
          context,
          _community,
          endCallsIn: ref.read(endCallsInProvider),
        );
        if (left && mounted) _close();
    }
  }

  Widget _roomRow(
    Room room,
    Map<String, int> corrections,
    DateTime now,
    DateLabels labels,
  ) {
    final data = chatRowDataFor(
      room,
      unreadCorrections: corrections,
      now: now,
      labels: labels,
    );
    return _memo.obtain(
      room.id,
      data,
      source: room,
      () => ChatRow(
        key: ValueKey(room.id),
        data: data,
        client: _client,
        preview: LastMessagePreview(
          room: room,
          event: room.lastEvent,
          summary: data.preview,
        ),
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
    } catch (e, s) {
      reportCaught('community members', e, s);
      people = community.getParticipants(shown);
    } finally {
      _loadingMembers = false;
    }
    if (!mounted) return;
    final user = await showMembersSheet(
      context,
      room: community,
      members: membersOwnerFirst(community, people),
      canManage: (user) => memberActionsFor(community, user).isNotEmpty,
    );
    if (user == null || !mounted) return;
    await _manageMember(user);
  }

  Future<void> _manageMember(User user) async {
    final community = _community;
    final action = await chooseMemberAction(context, community, user);
    if (action == null || !mounted) return;
    final bool changed;
    switch (action) {
      case MemberAction.changeRole:
        changed = await changeMemberRole(context, community, user);
      case MemberAction.remove || MemberAction.ban:
        changed = await removeMember(
          context,
          community,
          user,
          ban: action == MemberAction.ban,
        );
      case MemberAction.message || MemberAction.block || MemberAction.report:
        changed = false;
    }
    if (changed && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final corrections = ref.watch(callUnreadCorrectionProvider);
    final asked = ref.watch(joinRequestsProvider);
    return RoomChangesBuilder(
      changes: RoomChanges.where(_client, syncs: _concerns),
      onChange: _closeIfLeft,
      builder: (context) => _page(context, corrections, asked),
    );
  }

  Widget _page(
    BuildContext context,
    Map<String, int> corrections,
    Set<String> asked,
  ) {
    final community = _community;
    final rooms = communityRooms(community);
    _memo.retainOnly(rooms.map((room) => room.id));
    final positions = {for (var i = 0; i < rooms.length; i++) rooms[i].id: i};
    final joinable = _more
        ?.where(
          (c) => _client.getRoomById(c.roomId)?.membership != Membership.join,
        )
        .toList();
    final canInvite = community.canInvite;
    final canAddRooms = community.canChangeStateEvent(EventTypes.SpaceChild);
    final now = clock.now();
    final labels = DateLabels.of(context);
    final l10n = context.l10n;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final members =
        community.summary.mJoinedMemberCount ??
        community.getParticipants([Membership.join]).length;

    return Scaffold(
      appBar: AppBar(
        actions: [
          PopupMenuButton<_Menu>(
            tooltip: l10n.commonMore,
            onSelected: _onMenu,
            itemBuilder: (context) => [
              if (canEditRoomSettings(community))
                PopupMenuItem(
                  value: _Menu.settings,
                  child: Text(l10n.communitiesSettings),
                ),
              if (roomPermissionsAccessFor(community) !=
                  RoomPermissionsAccess.hidden)
                PopupMenuItem(
                  value: _Menu.permissions,
                  child: Text(l10n.roomInfoRolesAndPermissions),
                ),
              PopupMenuItem(
                value: _Menu.leave,
                child: Text(roomExitLabel(community, l10n)),
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
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: RoomHeader(
                  room: community,
                  details: [
                    RoomAccessLabel.of(community, l10n),
                    _MembersButton(count: members, onTap: _viewMembers),
                  ],
                ),
              ),
              if (canInvite || canAddRooms)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (canInvite)
                          Flexible(
                            child: QuickAction(
                              icon: Icons.person_add_alt_outlined,
                              label: l10n.commonInvite,
                              onTap: _invite,
                            ),
                          ),
                        if (canAddRooms)
                          Flexible(
                            child: QuickAction(
                              icon: Icons.add_comment_outlined,
                              label: l10n.roomsNewRoom,
                              onTap: _newRoom,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (rooms.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: SectionLabel(l10n.communitiesYourRooms),
                ),
                SliverList.builder(
                  itemCount: rooms.length,
                  findChildIndexCallback: (key) =>
                      key is ValueKey<String> ? positions[key.value] : null,
                  itemBuilder: (context, index) =>
                      _roomRow(rooms[index], corrections, now, labels),
                ),
              ],
              if (_failed)
                SliverToBoxAdapter(
                  child: FailureNotice(
                    message: l10n.communitiesLoadFailed,
                    onRetry: _loadMore,
                  ),
                )
              else if (joinable == null)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (joinable.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: SectionLabel(l10n.communitiesMoreRooms),
                ),
                SliverList.builder(
                  itemCount: joinable.length,
                  itemBuilder: (context, index) =>
                      _joinable(joinable[index], asked),
                ),
              ] else if (rooms.isEmpty)
                SliverToBoxAdapter(child: _NoRooms(canAddRooms: canAddRooms)),
              SliverToBoxAdapter(child: SizedBox(height: 24 + bottomInset)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MembersButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _MembersButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      minimumSize: const Size(0, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: Theme.of(context).textTheme.bodySmall,
    ),
    child: Text(
      context.l10n.unitsMembers(count),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );
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
    final l10n = context.l10n;
    final name = chunk.name?.trim();
    final title = name == null || name.isEmpty
        ? l10n.communitiesUnnamedRoom
        : name;
    final topic = chunk.topic?.trim();
    final detail = joinDetails([
      if (entry != _Entry.join) RoomAccess.askToJoin.label(l10n),
      l10n.unitsMembers(chunk.numJoinedMembers),
      if (topic != null && topic.isNotEmpty) topic,
    ]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: entry == _Entry.requested
                ? OutlinedButton(
                    onPressed: busy ? null : onTap,
                    child: Text(l10n.communitiesRequested),
                  )
                : FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.secondaryContainer,
                      foregroundColor: colors.onSecondaryContainer,
                    ),
                    onPressed: busy ? null : onTap,
                    child: Text(
                      entry == _Entry.ask
                          ? l10n.communitiesAsk
                          : l10n.commonJoin,
                    ),
                  ),
          ),
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
          Text(
            context.l10n.communitiesNoRooms,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            canAddRooms
                ? context.l10n.communitiesNoRoomsCanAdd
                : context.l10n.communitiesNoRoomsCannotAdd,
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
