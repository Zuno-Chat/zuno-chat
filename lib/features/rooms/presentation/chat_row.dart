import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/matrix/official_room.dart';
import '../../../core/security/security_emphasis.dart';
import '../../../core/ui/line_strut.dart';
import '../data/chat_row_data.dart';
import 'room_kind_avatar.dart';

class ChatRow extends StatelessWidget {
  static const avatarRadius = 26.0;

  final ChatRowData data;
  final Client client;
  final Widget preview;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const ChatRow({
    required this.data,
    required this.client,
    required this.preview,
    this.onTap,
    this.onLongPress,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mutedColor = scheme.onSurfaceVariant;
    final loud = data.unread > 0 && !data.muted;
    final statusIcon = data.muted
        ? Icons.notifications_off_outlined
        : data.awaitingAcceptance
        ? Icons.schedule_outlined
        : data.partnerLeft
        ? Icons.person_off_outlined
        : null;
    final secondLineStyle = theme.textTheme.bodyMedium!.copyWith(
      color: mutedColor,
    );

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            RoomKindAvatar(
              client: client,
              avatarUrl: data.avatarUrl,
              fallbackText: data.title,
              isDirect: data.isDirect,
              radius: avatarRadius,
              toneSeed: data.toneSeed,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (!data.encrypted) ...[
                        Icon(notEncryptedIcon, size: 14, color: scheme.error),
                        const SizedBox(width: 4),
                      ],
                      if (statusIcon != null) ...[
                        Icon(statusIcon, size: 14, color: mutedColor),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          data.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          strutStyle: lineStrut(theme.textTheme.titleMedium!),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: data.dimmed ? mutedColor : scheme.onSurface,
                          ),
                        ),
                      ),
                      if (data.official) ...[
                        const SizedBox(width: 6),
                        const OfficialBadge(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  DefaultTextStyle.merge(
                    style: secondLineStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: _secondLine(scheme, secondLineStyle),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  data.timeLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: loud ? scheme.onSurface : mutedColor,
                    fontWeight: loud ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 5),
                SizedBox(
                  height: 20,
                  child: data.unread > 0
                      ? _UnreadCount(count: data.unread, quiet: data.muted)
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _secondLine(ColorScheme scheme, TextStyle base) {
    Widget line(String text, TextStyle style) => Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      strutStyle: lineStrut(base),
      style: style,
    );

    final italic = base.copyWith(fontStyle: FontStyle.italic);
    final status = data.awaitingAcceptance
        ? data.pendingInviteSubtitle
        : data.partnerLeft
        ? 'Left the chat'
        : null;
    if (status != null) return line(status, italic);
    final typing = data.typingText;
    if (typing != null) {
      return line(typing, italic.copyWith(color: scheme.primary));
    }
    return preview;
  }
}

class _UnreadCount extends StatelessWidget {
  final int count;
  final bool quiet;

  const _UnreadCount({required this.count, required this.quiet});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mutedColor = scheme.onSurfaceVariant;
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: quiet ? null : scheme.primaryContainer,
        border: quiet ? Border.all(color: mutedColor, width: 1.5) : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 12,
          height: 1,
          fontWeight: FontWeight.w700,
          color: quiet ? mutedColor : scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
