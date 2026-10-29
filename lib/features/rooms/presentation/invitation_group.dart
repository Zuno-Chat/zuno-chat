import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/l10n/display_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/room_invite.dart';
import '../../../core/notifications/room_invite_notification_provider.dart';
import '../../../core/ui/notice.dart';
import '../../../core/ui/row_memo.dart';
import '../../../core/ui/zuno_theme.dart';
import 'room_invite_page.dart';

class InvitationGroup extends StatefulWidget {
  final List<Room> invitations;

  const InvitationGroup({required this.invitations, super.key});

  @override
  State<InvitationGroup> createState() => _InvitationGroupState();
}

class _InvitationGroupState extends State<InvitationGroup> {
  final _memo = RowMemo<(IncomingInviteView, BorderRadius)>();

  @override
  Widget build(BuildContext context) {
    final invitations = widget.invitations;
    _memo.retainOnly(invitations.map((room) => room.id));
    final positions = {
      for (var i = 0; i < invitations.length; i++) invitations[i].id: i,
    };

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final room = invitations[index];
            final corners = _cornersAt(index, invitations.length);
            return _memo.obtain(
              room.id,
              (incomingInviteView(room, context.l10n), corners),
              source: room,
              () => _Invitation(
                key: ValueKey(room.id),
                room: room,
                corners: corners,
              ),
            );
          },
          childCount: invitations.length,
          findChildIndexCallback: (key) =>
              key is ValueKey<String> ? positions[key.value] : null,
        ),
      ),
    );
  }
}

BorderRadius _cornersAt(int index, int count) {
  const corner = Radius.circular(ZunoRadius.large);
  return BorderRadius.vertical(
    top: index == 0 ? corner : Radius.zero,
    bottom: index == count - 1 ? corner : Radius.zero,
  );
}

String _invitedYou(IncomingInviteView view, AppLocalizations l10n) {
  if (view.community) return l10n.roomsInvitedYouToCommunity(view.inviterName);
  if (view.group) return l10n.roomsInvitedYou(view.inviterName);
  return l10n.roomsInvitedYouToChat;
}

class _Invitation extends StatefulWidget {
  final Room room;
  final BorderRadius corners;

  const _Invitation({required this.room, required this.corners, super.key});

  @override
  State<_Invitation> createState() => _InvitationState();
}

class _InvitationState extends State<_Invitation> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    loadInviteMembers(widget.room).then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _answer(
    Future<void> Function() action, {
    @displayText required String failed,
  }) async {
    setState(() => _busy = true);
    unawaited(cancelInviteNotification(widget.room));
    await attempt(context, action, label: 'answer invitation', failed: failed);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final view = incomingInviteView(room, l10n);

    return Material(
      color: theme.colorScheme.secondaryContainer,
      borderRadius: widget.corners,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => RoomInvitePage(room: room))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
          child: Column(
            children: [
              Row(
                children: [
                  MxcAvatar(
                    client: room.client,
                    avatarUrl: view.avatarUrl,
                    fallbackText: view.name,
                    radius: 26,
                    toneSeed: roomToneSeed(room),
                    shape: AvatarShape.forRoom(room),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          view.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _invitedYou(view, l10n),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _answer(
                            () => declineInvite(room),
                            failed: l10n.roomsCouldNotDecline,
                          ),
                    child: Text(l10n.commonDecline),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _answer(
                            () => acceptInvite(room),
                            failed: l10n.roomsCouldNotJoin,
                          ),
                    child: Text(l10n.commonJoin),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
