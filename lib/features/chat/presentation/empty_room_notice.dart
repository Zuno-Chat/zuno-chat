import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/l10n/l10n.dart';
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

    final l10n = context.l10n;
    final text = switch (trust) {
      null => l10n.chatEmptyEncryptedGroup,
      UserTrustState.noIdentity => l10n.chatEmptyEncryptedNoIdentity,
      UserTrustState.confirmed || UserTrustState.confirmedWithPendingDevice =>
        l10n.chatEmptyEncryptedConfirmed(name!),
      UserTrustState.unconfirmed || UserTrustState.identityChanged =>
        l10n.chatEmptyEncryptedUnconfirmed(name!),
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
              child: Text(l10n.chatWhyConfirm),
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
          ? context.l10n.chatConfirmAfterJoin(name)
          : null,
    );
    if (confirm != true || !context.mounted) return;
    await confirmPerson(context, ref, userId);
  }
}
