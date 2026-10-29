import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import '../../../core/calls/models/call_kind.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/mxc_avatar.dart';
import '../../../core/matrix/official_room.dart';
import '../../../core/matrix/room_changes.dart';
import '../../../core/matrix/room_encryption.dart';
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
    final l10n = context.l10n;
    final display = roomInviteDisplay(room, l10n);

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
              toneSeed: roomToneSeed(room),
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
                      if (!sendsEncrypted(room)) ...[
                        const SizedBox(width: 6),
                        const NotEncryptedMark(size: 18),
                      ],
                      ConfirmedPersonCheck(room: room),
                    ],
                  ),
                  RoomChangesBuilder(
                    changes: RoomChanges.ephemeral(room, 'm.typing'),
                    builder: (context) {
                      final typingText = typingIndicatorText(
                        l10n,
                        room.typingUsers
                            .where((u) => u.id != room.client.userID)
                            .toList(),
                      );
                      if (typingText != null) {
                        return _StatusLine(typingText, color: colors.primary);
                      }
                      if (display.partnerLeft) {
                        return _StatusLine(
                          l10n.chatLeftTheChat,
                          color: colors.onSurfaceVariant,
                        );
                      }
                      if (!room.isDirectChat) {
                        return RoomAccessLabel.of(room, l10n, iconSize: 14);
                      }
                      return const SizedBox.shrink();
                    },
                  ),
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
            tooltip: l10n.callsStartVoiceCall,
            onPressed: () => onStartCall(CallKind.voice),
          ),
          IconButton(
            icon: const Icon(Icons.videocam_outlined),
            tooltip: l10n.callsStartVideoCall,
            onPressed: () => onStartCall(CallKind.video),
          ),
        ],
        PopupMenuButton<void>(itemBuilder: menuBuilder),
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  final String text;
  final Color color;

  const _StatusLine(this.text, {required this.color});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall!.copyWith(color: color);
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
      strutStyle: lineStrut(style),
    );
  }
}
