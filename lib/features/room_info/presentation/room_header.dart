import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/room_invite.dart';
import 'room_topic.dart';

class RoomHeader extends StatelessWidget {
  final Room room;
  final List<Widget> details;

  const RoomHeader({required this.room, this.details = const [], super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final display = roomInviteDisplay(room, context.l10n);
    final topic = room.topic.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 18),
      child: Column(
        children: [
          MxcAvatar(
            client: room.client,
            avatarUrl: display.avatarUrl,
            fallbackText: display.title,
            toneSeed: roomToneSeed(room),
            radius: 44,
            shape: AvatarShape.forRoom(room),
          ),
          const SizedBox(height: 12),
          Text(
            display.title,
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (index, detail) in details.indexed) ...[
                  if (index > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text('•', style: theme.textTheme.bodySmall),
                    ),
                  Flexible(child: detail),
                ],
              ],
            ),
          ],
          if (topic.isNotEmpty) ...[
            const SizedBox(height: 12),
            RoomTopic(topic: topic),
          ],
        ],
      ),
    );
  }
}
