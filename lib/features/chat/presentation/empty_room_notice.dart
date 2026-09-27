import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/matrix/matrix_ids.dart';
import '../../../core/matrix/room_invite.dart';
import '../../../core/security/security_providers.dart';
import '../../../core/security/user_trust.dart';
import '../../verification/presentation/confirm_person.dart';
import '../../verification/presentation/why_confirm_sheet.dart';

class EmptyRoomNotice extends ConsumerWidget {
  final Room room;

  const EmptyRoomNotice({required this.room, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!room.encrypted) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final otherId = room.isDirectChat ? room.directChatMatrixID : null;
    final trust = otherId == null
        ? null
        : ref.watch(userTrustProvider(otherId));
    final name = otherId == null ? null : withoutServer(otherId);

    const encrypted = 'Messages here are end-to-end encrypted.';
    final text = switch (trust) {
      null => '$encrypted Only the people in this chat can read them.',
      UserTrustState.noIdentity => encrypted,
      UserTrustState.confirmed || UserTrustState.confirmedWithPendingDevice =>
        '$encrypted Only you and $name can read them.',
      UserTrustState.unconfirmed || UserTrustState.identityChanged =>
        '$encrypted Once you confirm it is really $name, only the two of '
            'you can read them.',
    };
    final offersWhy =
        trust == UserTrustState.unconfirmed ||
        trust == UserTrustState.identityChanged;

    return Padding(
      padding: EdgeInsets.fromLTRB(32, 32, 32, offersWhy ? 16 : 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, size: 28, color: colors.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          if (offersWhy) ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => _explain(context, ref, otherId!),
              child: const Text('Why confirm'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _explain(
    BuildContext context,
    WidgetRef ref,
    String userId,
  ) async {
    final name = withoutServer(userId);
    final confirm = await showWhyConfirmSheet(
      context,
      name: name,
      unavailableReason: isAwaitingInviteAcceptance(room)
          ? 'You can confirm $name once they join.'
          : null,
    );
    if (confirm != true || !context.mounted) return;
    await confirmPerson(context, ref, userId);
  }
}
