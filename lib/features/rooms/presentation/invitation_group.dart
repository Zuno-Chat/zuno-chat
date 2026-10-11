import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/caught_errors.dart';
import '../../../core/errors/connection_error.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/room_invite.dart';
import '../../../core/notifications/invite_notification_provider.dart';
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
  final _memo = RowMemo<(_InvitationView, BorderRadius)>();

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
              (_viewOf(room), corners),
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

typedef _InvitationView = ({
  String name,
  String subtitle,
  Uri? avatarUrl,
  String toneSeed,
  AvatarShape shape,
});

_InvitationView _viewOf(Room room) {
  final inviter = inviterId(room);
  final inviterUser = inviter == null
      ? null
      : room.unsafeGetUserFromMemoryOrFallback(inviter);
  final inviterName = inviterUser?.calcDisplayname() ?? 'Someone';
  final isGroup = room.name.isNotEmpty;
  final String subtitle;
  if (room.isSpace) {
    subtitle = '$inviterName invited you to a community';
  } else if (isGroup) {
    subtitle = '$inviterName invited you';
  } else {
    subtitle = 'Invited you to chat';
  }
  return (
    name: isGroup ? room.name : inviterName,
    subtitle: subtitle,
    avatarUrl: isGroup ? room.avatar : inviterUser?.avatarUrl,
    toneSeed: roomToneSeed(room),
    shape: AvatarShape.forRoom(room),
  );
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
    required String failed,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    unawaited(cancelInviteNotification(widget.room));
    try {
      await action();
    } catch (e, s) {
      reportCaught('answer invitation', e, s);
      messenger.showSnackBar(
        SnackBar(content: Text(failureMessage(e, failed: failed))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final theme = Theme.of(context);
    final view = _viewOf(room);

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
                    toneSeed: view.toneSeed,
                    shape: view.shape,
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
                          view.subtitle,
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
                            failed: 'Could not decline.',
                          ),
                    child: const Text('Decline'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _answer(
                            () => acceptInvite(room),
                            failed: 'Could not join.',
                          ),
                    child: const Text('Join'),
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
