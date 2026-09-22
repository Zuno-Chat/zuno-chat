import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/security/security_providers.dart';
import '../../../core/security/user_trust.dart';

class ConfirmedPersonCheck extends ConsumerWidget {
  final Room room;

  const ConfirmedPersonCheck({required this.room, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = room.directChatMatrixID;
    if (!room.isDirectChat || userId == null) return const SizedBox.shrink();

    final state = ref.watch(userTrustProvider(userId));
    final confirmed =
        state == UserTrustState.confirmed ||
        state == UserTrustState.confirmedWithPendingDevice;
    if (!confirmed) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Icon(
        Icons.check_circle_outline,
        size: 18,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        semanticLabel: 'Confirmed',
      ),
    );
  }
}
