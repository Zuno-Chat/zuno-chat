import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/matrix/room_invite.dart';
import '../../../core/ui/empty_state.dart';
import '../../../core/ui/row_memo.dart';
import '../../../core/ui/section_label.dart';
import '../../chat/presentation/chat_wallpaper.dart';
import '../data/chat_row_data.dart';
import 'chat_row.dart';
import 'invitation_group.dart';
import 'last_message_preview.dart';

class ChatListView extends StatefulWidget {
  final Client client;
  final List<Room> rooms;
  final Map<String, int> unreadCorrections;
  final void Function(Room room) onOpen;
  final void Function(Room room) onActions;

  const ChatListView({
    required this.client,
    required this.rooms,
    required this.unreadCorrections,
    required this.onOpen,
    required this.onActions,
    super.key,
  });

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
    final invitations = widget.rooms.where(isIncomingInvite).toList();
    final chats = widget.rooms.where((r) => !isIncomingInvite(r)).toList();
    const physics = AlwaysScrollableScrollPhysics();
    _memo.retainOnly(chats.map((room) => room.id));

    if (invitations.isEmpty && chats.isEmpty) {
      return const CustomScrollView(
        physics: physics,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.chat_bubble_outline,
              title: 'No chats yet',
              body: 'Tap + to start one.',
            ),
          ),
        ],
      );
    }

    final now = DateTime.now();
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final positions = {for (var i = 0; i < chats.length; i++) chats[i].id: i};

    return CustomScrollView(
      physics: physics,
      slivers: [
        if (invitations.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionLabel('Invitations')),
          SliverToBoxAdapter(child: InvitationGroup(invitations: invitations)),
          if (chats.isNotEmpty)
            const SliverToBoxAdapter(child: SectionLabel('Chats')),
        ],
        SliverPrototypeExtentList(
          prototypeItem: _prototype,
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final room = chats[index];
              final data = chatRowDataFor(
                room,
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
                  preview: LastMessagePreview(
                    room: room,
                    event: room.lastEvent,
                  ),
                  onTap: () => widget.onOpen(room),
                  onLongPress: () => widget.onActions(room),
                ),
              );
            },
            childCount: chats.length,
            findChildIndexCallback: (key) =>
                key is ValueKey<String> ? positions[key.value] : null,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 88)),
      ],
    );
  }
}
