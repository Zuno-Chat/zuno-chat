import 'package:flutter/material.dart';

import '../../../core/matrix/room_access.dart';

class RoomAccessLabel extends StatelessWidget {
  final RoomAccess access;
  final double iconSize;

  const RoomAccessLabel({required this.access, this.iconSize = 16, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          access == RoomAccess.public ? Icons.public : Icons.public_off,
          size: iconSize,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(access.label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
