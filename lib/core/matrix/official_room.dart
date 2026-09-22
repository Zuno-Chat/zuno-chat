import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

const officialNoticesUserId = '@notices:zuno.chat';

bool isOfficialZunoRoom(Room room) {
  if (!room.tags.containsKey(TagType.serverNotice)) return false;
  return room.getState(EventTypes.RoomCreate)?.senderId ==
      officialNoticesUserId;
}

class OfficialBadge extends StatelessWidget {
  const OfficialBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.verified_outlined, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          'Official',
          style: theme.textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}
