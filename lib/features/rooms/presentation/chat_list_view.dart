import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/format/date_labels.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/communities.dart';
import '../../../core/ui/empty_state.dart';
import '../../../core/ui/row_memo.dart';
import '../../../core/ui/section_label.dart';
import '../../chat/presentation/chat_wallpaper.dart';
import '../data/chat_row_data.dart';
import 'chat_row.dart';
import 'community_preview.dart';
import 'home_bottom_bar.dart';
import 'invitation_group.dart';
import 'last_message_preview.dart';

class ChatListView extends StatefulWidget {
  final Client client;
  final List<Room> invitations;
  final List<Room> rows;
  final Map<String, List<Room>> communityRooms;
  final HomeTab section;
  final bool loading;
  final Map<String, int> unreadCorrections;
  final void Function(Room room) onOpen;
  final void Function(Room room) onActions;

  ChatListView.chats({
    required this.client,
    required HomeLayout layout,
    required this.unreadCorrections,
    required this.onOpen,
    required this.onActions,
    this.loading = false,
    super.key,
  }) : invitations = layout.chatInvitations,
       rows = layout.chats,
       communityRooms = const {},
       section = HomeTab.chats;

  ChatListView.communities({
    required this.client,
    required HomeLayout layout,
    required this.unreadCorrections,
    required this.onOpen,
    required this.onActions,
    this.loading = false,
    super.key,
  }) : invitations = layout.communityInvitations,
       rows = layout.communities,
       communityRooms = layout.communityRooms,
       section = HomeTab.communities;

  @override
  State<ChatListView> createState() => _ChatListViewState();
}

class _ChatListViewState extends State<ChatListView> {
  final _memo = RowMemo<ChatRowData>();

  ChatRow get _prototype => ChatRow(
    data: ChatRowData.prototype,
    client: widget.client,
    preview: Text(context.l10n.roomsPreviewSample),
  );

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

  @override
  Widget build(BuildContext context) {
    final invitations = widget.invitations;
    final rows = widget.rows;
    const physics = AlwaysScrollableScrollPhysics();
    final l10n = context.l10n;
    final storage = PageStorageKey<String>(widget.section.name);
    _memo.retainOnly(rows.map((room) => room.id));

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
    final positions = {for (var i = 0; i < rows.length; i++) rows[i].id: i};

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
        SliverPrototypeExtentList(
          prototypeItem: _prototype,
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final room = rows[index];
              final inside = widget.communityRooms[room.id];
              final data = inside == null
                  ? chatRowDataFor(
                      room,
                      unreadCorrections: widget.unreadCorrections,
                      now: now,
                      labels: labels,
                    )
                  : communityRowDataFor(
                      room,
                      inside,
                      unreadCorrections: widget.unreadCorrections,
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
                  client: widget.client,
                  preview: inside == null
                      ? LastMessagePreview(room: room, event: room.lastEvent)
                      : CommunityPreview(room: inside.firstOrNull),
                  onTap: () => widget.onOpen(room),
                  onLongPress: () => widget.onActions(room),
                ),
              );
            },
            childCount: rows.length,
            findChildIndexCallback: (key) =>
                key is ValueKey<String> ? positions[key.value] : null,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
      ],
    );
  }
}
