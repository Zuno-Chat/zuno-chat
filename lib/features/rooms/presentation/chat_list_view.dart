import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/matrix/communities.dart';
import '../../../core/ui/empty_state.dart';
import '../../../core/ui/row_memo.dart';
import '../../../core/ui/section_label.dart';
import '../../chat/presentation/chat_wallpaper.dart';
import '../data/chat_row_data.dart';
import 'chat_row.dart';
import 'community_preview.dart';
import 'invitation_group.dart';
import 'last_message_preview.dart';

class ChatListView extends StatefulWidget {
  final Client client;
  final List<Room> invitations;
  final List<Room> rows;
  final Map<String, List<Room>> communityRooms;
  final String rowsLabel;
  final EmptyState empty;
  final Map<String, int> unreadCorrections;
  final void Function(Room room) onOpen;
  final void Function(Room room) onActions;

  ChatListView.chats({
    required this.client,
    required HomeLayout layout,
    required this.unreadCorrections,
    required this.onOpen,
    required this.onActions,
    super.key,
  }) : invitations = layout.chatInvitations,
       rows = layout.chats,
       communityRooms = const {},
       rowsLabel = 'Chats',
       empty = const EmptyState(
         icon: Icons.chat_bubble_outline,
         title: 'No chats yet',
         body: 'Tap + to start one.',
       );

  ChatListView.communities({
    required this.client,
    required HomeLayout layout,
    required this.unreadCorrections,
    required this.onOpen,
    required this.onActions,
    super.key,
  }) : invitations = layout.communityInvitations,
       rows = layout.communities,
       communityRooms = layout.communityRooms,
       rowsLabel = 'Communities',
       empty = const EmptyState(
         icon: Icons.workspaces_outlined,
         title: 'No communities yet',
         body: 'Tap + to start one or find a public one.',
       );

  @override
  State<ChatListView> createState() => _ChatListViewState();
}

class _ChatListViewState extends State<ChatListView> {
  final _memo = RowMemo<ChatRowData>();

  late final _prototype = ChatRow(
    data: ChatRowData.prototype,
    client: widget.client,
    preview: const Text('Preview'),
  );

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
    final storage = PageStorageKey<String>(widget.rowsLabel);
    _memo.retainOnly(rows.map((room) => room.id));

    if (invitations.isEmpty && rows.isEmpty) {
      return CustomScrollView(
        key: storage,
        physics: physics,
        slivers: [
          SliverFillRemaining(hasScrollBody: false, child: widget.empty),
        ],
      );
    }

    final now = DateTime.now();
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final positions = {for (var i = 0; i < rows.length; i++) rows[i].id: i};

    return CustomScrollView(
      key: storage,
      physics: physics,
      slivers: [
        if (invitations.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionLabel('Invitations')),
          SliverToBoxAdapter(child: InvitationGroup(invitations: invitations)),
          if (rows.isNotEmpty)
            SliverToBoxAdapter(child: SectionLabel(widget.rowsLabel)),
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
                      use24Hour: use24Hour,
                    )
                  : communityRowDataFor(
                      room,
                      inside,
                      unreadCorrections: widget.unreadCorrections,
                      now: now,
                      use24Hour: use24Hour,
                    );
              return _memo.obtain(
                room.id,
                data,
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
