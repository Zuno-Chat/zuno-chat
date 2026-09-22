import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/matrix/matrix_ids.dart';
import '../../../core/security/security_emphasis.dart';
import '../../../core/security/security_providers.dart';
import '../../../core/security/user_trust.dart';
import '../../verification/presentation/confirm_person.dart';

class IdentityChangeBanner extends ConsumerWidget {
  final Room room;

  const IdentityChangeBanner({required this.room, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final others = room
        .getParticipants([Membership.join, Membership.invite])
        .map((u) => u.id)
        .where((id) => id != room.client.userID)
        .toList();

    final changed = others
        .where(
          (id) =>
              ref.watch(userTrustProvider(id)) ==
              UserTrustState.identityChanged,
        )
        .toList();
    if (changed.isEmpty) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.errorContainer,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AttentionStripe(),
            Expanded(child: _body(context, colors, changed)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, ColorScheme colors, List<String> changed) {
    final name = withoutServer(changed.first);
    return Consumer(
      builder: (context, ref, _) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            Icon(attentionIcon, color: colors.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    changed.length == 1
                        ? "$name's security details changed"
                        : "${changed.length} people's security details changed",
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onErrorContainer,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    'Usually a new device or a reinstall. It can also mean '
                    'someone is listening in.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.onErrorContainer),
                  ),
                ],
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              onPressed: () => confirmPerson(context, ref, changed.first),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
  }
}
