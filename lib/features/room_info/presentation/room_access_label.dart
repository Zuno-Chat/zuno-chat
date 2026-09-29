import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/matrix/communities.dart';
import '../../../core/matrix/room_access.dart';

class RoomAccessLabel extends StatelessWidget {
  final RoomAccess access;
  final String? community;
  final double iconSize;

  const RoomAccessLabel({
    required this.access,
    this.community,
    this.iconSize = 16,
    super.key,
  });

  factory RoomAccessLabel.of(Room room, {double iconSize = 16, Key? key}) {
    final access = roomAccessOf(room);
    return RoomAccessLabel(
      access: access,
      community: access == RoomAccess.community ? communityNameOf(room) : null,
      iconSize: iconSize,
      key: key,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          switch (access) {
            RoomAccess.public => Icons.public,
            RoomAccess.community => Icons.workspaces_outlined,
            RoomAccess.askToJoin => Icons.front_hand_outlined,
            RoomAccess.private => Icons.public_off,
          },
          size: iconSize,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            access == RoomAccess.community
                ? community ?? access.label
                : access.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
