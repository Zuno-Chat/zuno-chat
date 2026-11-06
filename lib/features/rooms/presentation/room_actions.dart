import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart';

import '../../../core/calls/end_call.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/matrix/events/read_receipts.dart';
import '../../../core/matrix/rooms/membership/room_exit.dart';
import '../../../core/matrix/rooms/room_mute.dart';
import '../../../core/ui/notice.dart';
import '../../../core/ui/sheet.dart';

enum _RoomAction { markRead, mute, unmute, exit }

Future<void> showRoomActions(
  BuildContext context,
  WidgetRef ref,
  Room room,
) async {
  final l10n = context.l10n;
  final isCommunity = room.isSpace;
  final hasUnread = !isCommunity && room.notificationCount > 0;

  final action = await showActionSheet(
    context,
    actions: [
      if (hasUnread)
        SheetAction(
          _RoomAction.markRead,
          icon: Icons.mark_chat_read_outlined,
          label: l10n.commonMarkAsRead,
        ),
      if (!isCommunity)
        isRoomMuted(room)
            ? SheetAction(
                _RoomAction.unmute,
                icon: Icons.notifications_active_outlined,
                label: l10n.roomsUnmute,
              )
            : SheetAction(
                _RoomAction.mute,
                icon: Icons.notifications_off_outlined,
                label: l10n.roomsMute,
              ),
      SheetAction(
        _RoomAction.exit,
        icon: roomExitIcon(room),
        label: roomExitLabel(room, l10n),
        destructive: true,
      ),
    ],
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case _RoomAction.markRead:
      await attempt(
        context,
        () async {
          final eventId = await newestReadMarkerEventId(room);
          if (eventId == null) return;
          await markRoomRead(room, eventId);
        },
        label: 'room action mark read',
        failed: l10n.roomsNotMarkedAsRead,
      );
    case _RoomAction.mute || _RoomAction.unmute:
      await askToMuteRoom(context, room, action == _RoomAction.mute);
    case _RoomAction.exit:
      await confirmAndExitRoom(
        context,
        room,
        endCallsIn: ref.read(endCallsInProvider),
      );
  }
}
