import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/matrix/matrix_ids.dart';
import '../../../core/matrix/room_access.dart';
import '../../../core/security/security_emphasis.dart';
import '../../../core/security/unverified_device_warning.dart';
import '../../../core/security/unverified_device_warning_provider.dart';

class UnvouchedDeviceBanner extends ConsumerWidget {
  final Room room;

  const UnvouchedDeviceBanner({required this.room, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (roomAccessOf(room) == RoomAccess.public) return const SizedBox.shrink();
    final flagged = ref.watch(unvouchedDeviceWarningProvider);
    if (flagged.isEmpty) return const SizedBox.shrink();

    final ownId = room.client.userID;
    final here = room
        .getParticipants([Membership.join])
        .where((u) => u.id != ownId && flagged.contains(u.id))
        .toList();
    if (here.isEmpty) return const SizedBox.shrink();

    final user = here.first;
    final displayName = user.calcDisplayname();
    final text = unvouchedDeviceWarningText(
      displayName.isNotEmpty ? displayName : withoutServer(user.id),
    );
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: colors.errorContainer,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AttentionStripe(),
            Expanded(
              child: Padding(
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
                            text.title,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: colors.onErrorContainer,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                          Text(
                            text.body,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colors.onErrorContainer),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => ref
                          .read(unvouchedDeviceWarningProvider.notifier)
                          .dismiss(user.id),
                      child: Text(
                        'Dismiss',
                        style: TextStyle(color: colors.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
