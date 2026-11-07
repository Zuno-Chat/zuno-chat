import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/l10n/display_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/media/avatars/mxc_avatar.dart';
import '../../../core/matrix/rooms/membership/room_invite.dart';
import 'room_topic.dart';

class RoomHeader extends StatelessWidget {
  final Client client;
  final Uri? avatarUrl;
  final String title;
  final String toneSeed;
  final AvatarShape shape;
  final String? address;
  final List<Widget> details;
  final String? topic;

  const RoomHeader({
    required this.client,
    required this.avatarUrl,
    required this.title,
    required this.toneSeed,
    this.shape = AvatarShape.circle,
    this.address,
    this.details = const [],
    this.topic,
    super.key,
  });

  factory RoomHeader.of(
    Room room,
    AppLocalizations l10n, {
    List<Widget> details = const [],
    Key? key,
  }) {
    final display = roomInviteDisplay(room, l10n);
    return RoomHeader(
      client: room.client,
      avatarUrl: display.avatarUrl,
      title: display.title,
      toneSeed: roomToneSeed(room),
      shape: AvatarShape.forRoom(room),
      details: details,
      topic: room.topic,
      key: key,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topic = this.topic?.trim() ?? '';
    final address = this.address?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 18),
      child: Column(
        children: [
          MxcAvatar(
            client: client,
            avatarUrl: avatarUrl,
            fallbackText: title,
            toneSeed: toneSeed,
            radius: 44,
            shape: shape,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          if (address.isNotEmpty && address != title) ...[
            const SizedBox(height: 2),
            Text(
              address,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
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

class EncryptedLabel extends StatelessWidget {
  const EncryptedLabel({super.key});

  @override
  Widget build(BuildContext context) =>
      RoomDetail(context.l10n.roomInfoEncrypted, icon: Icons.lock_outline);
}

class RoomDetail extends StatelessWidget {
  final String text;
  final IconData? icon;
  final double iconSize;

  const RoomDetail(
    @displayText this.text, {
    this.icon,
    this.iconSize = 16,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = this.icon;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: iconSize, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
