import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/matrix/matrix_ids.dart';

class EmptyRoomNotice extends StatelessWidget {
  final Room room;

  const EmptyRoomNotice({required this.room, super.key});

  @override
  Widget build(BuildContext context) {
    if (!room.encrypted) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;
    final otherId = room.directChatMatrixID;
    final who = room.isDirectChat && otherId != null
        ? 'you and ${withoutServer(otherId)}'
        : 'the people in this chat';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, size: 28, color: colors.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            'Messages here are end-to-end encrypted. Only $who can read '
            'them.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
