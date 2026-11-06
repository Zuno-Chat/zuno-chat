import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/l10n/display_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/media/avatars/mxc_avatar.dart';
import '../../../core/matrix/rooms/membership/room_invite.dart';
import '../../../core/notifications/room_invite_notification_provider.dart';
import '../../../core/ui/card_group.dart';
import '../../../core/ui/notice.dart';
import '../../../core/ui/row_memo.dart';
import 'room_invite_page.dart';

class InvitationGroup extends StatefulWidget {
  final List<Room> invitations;

  const InvitationGroup({required this.invitations, super.key});

  @override
  State<InvitationGroup> createState() => _InvitationGroupState();
}

class _InvitationGroupState extends State<InvitationGroup> {
  final _memo = RowMemo<IncomingInviteView>();

  @override
  Widget build(BuildContext context) {
    final invitations = widget.invitations;
    _memo.retainOnly(invitations.map((room) => room.id));

    return SliverCardGroup(
      highlighted: true,
      itemCount: invitations.length,
      findChildIndexCallback: rowIndexById([
        for (final room in invitations) room.id,
      ]),
      itemBuilder: (context, index) {
        final room = invitations[index];
        return _memo.obtain(
          room.id,
          incomingInviteView(room, context.l10n),
          source: room,
          () => _Invitation(key: ValueKey(room.id), room: room),
        );
      },
    );
  }
}

String _invitedYou(IncomingInviteView view, AppLocalizations l10n) {
  if (view.community) return l10n.roomsInvitedYouToCommunity(view.inviterName);
  if (view.group) return l10n.roomsInvitedYou(view.inviterName);
  return l10n.roomsInvitedYouToChat;
}

class _Invitation extends StatefulWidget {
  final Room room;

  const _Invitation({required this.room, super.key});

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

    return InkWell(
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => RoomInvitePage(room: room))),
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
    );
  }
}
