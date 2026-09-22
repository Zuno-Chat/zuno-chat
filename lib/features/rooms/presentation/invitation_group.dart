import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/matrix/matrix_ids.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/room_invite.dart';
import '../../../core/notifications/invite_notification_provider.dart';
import '../../../core/ui/zuno_theme.dart';
import 'room_invite_page.dart';

class InvitationGroup extends StatelessWidget {
  final List<Room> invitations;

  const InvitationGroup({required this.invitations, super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(ZunoRadius.large),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (final room in invitations)
              _Invitation(key: ValueKey(room.id), room: room),
          ],
        ),
      ),
    );
  }
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

  Future<void> _answer(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    unawaited(cancelInviteNotification(widget.room));
    try {
      await action();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final theme = Theme.of(context);
    final inviter = inviterId(room);
    final inviterUser = inviter == null
        ? null
        : room.unsafeGetUserFromMemoryOrFallback(inviter);
    final isGroup = room.name.isNotEmpty;
    final name = isGroup
        ? room.name
        : inviterUser?.calcDisplayname() ??
              (inviter == null ? 'Someone' : withoutServer(inviter));

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
                  avatarUrl: isGroup ? room.avatar : inviterUser?.avatarUrl,
                  fallbackText: name,
                  radius: 26,
                  toneSeed: isGroup ? room.id : inviter,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isGroup
                            ? '${inviterUser?.calcDisplayname() ?? 'Someone'} '
                                  'invited you'
                            : 'Invited you to chat',
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
                      : () => _answer(() => declineInvite(room)),
                  child: const Text('Decline'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _answer(() => acceptInvite(room)),
                  child: const Text('Join'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
