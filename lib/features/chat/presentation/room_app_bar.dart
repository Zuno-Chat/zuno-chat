import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import '../../../core/calls/models/call_kind.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/official_room.dart';
import '../../../core/matrix/room_access.dart';
import '../../../core/matrix/room_invite.dart';
import '../../../core/matrix/typing_indicator_text.dart';
import '../../../core/security/security_emphasis.dart';
import '../../../core/ui/line_strut.dart';
import '../../room_info/presentation/room_access_label.dart';
import 'confirmed_person_check.dart';

class RoomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Room room;
  final bool canCall;
  final VoidCallback onOpenInfo;
  final void Function(CallKind kind) onStartCall;
  final List<PopupMenuEntry<void>> Function(BuildContext context) menuBuilder;

  const RoomAppBar({
    super.key,
    required this.room,
    required this.canCall,
    required this.onOpenInfo,
    required this.onStartCall,
    required this.menuBuilder,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final display = roomInviteDisplay(room);
    final ownUserId = room.client.userID;
    final typingText = typingIndicatorText(
      room.typingUsers.where((u) => u.id != ownUserId).toList(),
    );

    Widget statusLine(String text, Color color) {
      final style = theme.textTheme.bodySmall!.copyWith(color: color);
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
        strutStyle: lineStrut(style),
      );
    }

    return AppBar(
      leadingWidth: 48,
      titleSpacing: 0,
      title: InkWell(
        onTap: onOpenInfo,
        child: Row(
          children: [
            MxcAvatar(
              client: room.client,
              avatarUrl: display.avatarUrl,
              fallbackText: display.title,
              toneSeed: room.directChatMatrixID ?? room.id,
              radius: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          display.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      if (isOfficialZunoRoom(room)) ...[
                        const SizedBox(width: 6),
                        const OfficialBadge(),
                      ],
                      if (!room.encrypted) ...[
                        const SizedBox(width: 6),
                        Icon(notEncryptedIcon, size: 18, color: colors.error),
                      ],
                      ConfirmedPersonCheck(room: room),
                    ],
                  ),
                  if (typingText != null)
                    statusLine(typingText, colors.primary)
                  else if (display.partnerLeft)
                    statusLine('Left the chat', colors.onSurfaceVariant)
                  else if (!room.isDirectChat)
                    RoomAccessLabel(access: roomAccessOf(room), iconSize: 14),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (canCall) ...[
          IconButton(
            icon: const Icon(Icons.call_outlined),
            tooltip: 'Voice call',
            onPressed: () => onStartCall(CallKind.voice),
          ),
          IconButton(
            icon: const Icon(Icons.videocam_outlined),
            tooltip: 'Video call',
            onPressed: () => onStartCall(CallKind.video),
          ),
        ],
        PopupMenuButton<void>(itemBuilder: menuBuilder),
      ],
    );
  }
}
