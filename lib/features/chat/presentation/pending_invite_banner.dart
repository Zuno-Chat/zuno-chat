import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/matrix/room_invite.dart';

class PendingInviteBanner extends StatelessWidget {
  final Room room;

  const PendingInviteBanner({required this.room, super.key});

  @override
  Widget build(BuildContext context) {
    if (!isAwaitingInviteAcceptance(room)) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Icon(
              Icons.schedule_outlined,
              size: 20,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pendingInviteSubtitle(room),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    "Your messages will be here when they join.",
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
