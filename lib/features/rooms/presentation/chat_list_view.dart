import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/format/date_labels.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/media/avatars/mxc_avatar.dart';
import '../../../core/matrix/rooms/communities.dart';
import '../../../core/matrix/rooms/room_title.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/empty_state.dart';
import '../../../core/ui/row_memo.dart';
import '../../../core/ui/section_label.dart';
import '../../chat/presentation/chat_wallpaper.dart';
import '../data/chat_row_data.dart';
import 'chat_row.dart';
import 'home_bottom_bar.dart';
import 'invitation_group.dart';
import 'room_kind_avatar.dart';

const _headingAvatarRadius = 17.0;

class ChatListView extends StatefulWidget {
  final Client client;
  final HomeLayout layout;
  final HomeTab section;
  final bool loading;
  final Map<String, int> unreadCorrections;
  final void Function(Room room) onOpen;
  final void Function(Room room) onActions;

  const ChatListView({
    required this.client,
    required this.layout,
    required this.section,
    required this.unreadCorrections,
    required this.onOpen,
    required this.onActions,
    this.loading = false,
    super.key,
  });

  List<Room> get invitations => switch (section) {
    HomeTab.chats => layout.chatInvitations,
    HomeTab.communities => layout.communityInvitations,
  };

  List<Room> get rows => switch (section) {
    HomeTab.chats => layout.chats,
    HomeTab.communities => layout.communities,
  };

  @override
  State<ChatListView> createState() => _ChatListViewState();
}

class _ChatListViewState extends State<ChatListView> {
  final _memo = RowMemo<ChatRowData>();
  ChatRow? _prototype;

  ChatRow get _rowPrototype => _prototype ??= ChatRow(
    data: ChatRowData.prototype,
    client: widget.client,
    preview: Text(context.l10n.roomsPreviewSample),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _prototype = null;
  }

  EmptyState _emptyState(AppLocalizations l10n) => switch (widget.section) {
    HomeTab.chats => EmptyState(
      icon: Icons.chat_bubble_outline,
      title: l10n.roomsNoChatsYet,
      body: l10n.roomsNoChatsHint,
    ),
    HomeTab.communities => EmptyState(
      icon: Icons.workspaces_outlined,
      title: l10n.roomsNoCommunitiesYet,
      body: l10n.roomsNoCommunitiesHint,
    ),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(precacheChatWallpaper(context));
    });
  }

  List<Room> _roomsOf(Room community) =>
      widget.layout.communityRooms[community.id] ?? const [];

  Widget _row(
    Room room,
    DateTime now,
    DateLabels labels, {
    bool compact = false,
  }) => roomChatRow(
    _memo,
    room,
    unreadCorrections: widget.unreadCorrections,
    now: now,
    labels: labels,
    onOpen: widget.onOpen,
    onActions: widget.onActions,
    compact: compact,
  );

  Widget _chats(List<Room> rooms, DateTime now, DateLabels labels) =>
      SliverPrototypeExtentList(
        prototypeItem: _rowPrototype,
        delegate: SliverChildBuilderDelegate(
          (context, index) => _row(rooms[index], now, labels),
          childCount: rooms.length,
          findChildIndexCallback: rowIndexById([
            for (final room in rooms) room.id,
          ]),
        ),
      );

  Widget _communityCard(Room community, DateTime now, DateLabels labels) {
    final rooms = _roomsOf(community);
    final title = roomTitle(community, labels.l10n);
    return SliverCardGroup(
      key: ValueKey(community.id),
      title: title,
      leading: RoomKindAvatar(
        client: community.client,
        avatarUrl: community.avatar,
        fallbackText: title,
        isDirect: false,
        community: true,
        radius: _headingAvatarRadius,
        toneSeed: roomToneSeed(community),
      ),
      onTitleTap: () => widget.onOpen(community),
      onTitleLongPress: () => widget.onActions(community),
      itemCount: rooms.isEmpty ? 1 : rooms.length,
      findChildIndexCallback: rowIndexById([for (final room in rooms) room.id]),
      itemBuilder: (context, index) => rooms.isEmpty
          ? _NoRoomsJoined(onTap: () => widget.onOpen(community))
          : _row(rooms[index], now, labels, compact: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final invitations = widget.invitations;
    final rows = widget.rows;
    const physics = AlwaysScrollableScrollPhysics();
    final l10n = context.l10n;
    final storage = PageStorageKey<String>(widget.section.name);
    _memo.retainOnly(switch (widget.section) {
      HomeTab.chats => rows.map((room) => room.id),
      HomeTab.communities => rows.expand(_roomsOf).map((room) => room.id),
    });

    if (invitations.isEmpty && rows.isEmpty) {
      return CustomScrollView(
        key: storage,
        physics: physics,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: widget.loading
                ? const Center(child: CircularProgressIndicator())
                : _emptyState(l10n),
          ),
        ],
      );
    }

    final now = clock.now();
    final labels = DateLabels.of(context);

    return CustomScrollView(
      key: storage,
      physics: physics,
      slivers: [
        if (invitations.isNotEmpty) ...[
          SliverToBoxAdapter(child: SectionLabel(l10n.roomsInvitations)),
          InvitationGroup(invitations: invitations),
          if (rows.isNotEmpty)
            SliverToBoxAdapter(child: SectionLabel(widget.section.label(l10n))),
        ],
        ...switch (widget.section) {
          HomeTab.chats => [_chats(rows, now, labels)],
          HomeTab.communities => [
            for (final community in rows)
              _communityCard(community, now, labels),
          ],
        },
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
      ],
    );
  }
}

class _NoRoomsJoined extends StatelessWidget {
  final VoidCallback onTap;

  const _NoRoomsJoined({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 16),
        child: Text(
          context.l10n.roomsNoRoomsJoined,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
