import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../calls/end_call.dart';
import '../errors/caught_errors.dart';
import '../errors/connection_error.dart';
import '../l10n/l10n.dart';
import 'communities.dart';
import 'room_roles.dart';
import 'room_title.dart';

Future<void> exitRoom(Room room, {required bool isDirect}) async {
  if (room.isSpace) return leaveCommunity(room);
  if (room.membership != Membership.leave) await room.leave();
  if (!isDirect) return;
  try {
    await room.forget();
  } catch (e, s) {
    reportCaught('forget a deleted chat', e, s);
  }
}

Iterable<String> _roomIdsLeftBy(Room room) => [
  room.id,
  if (room.isSpace) ...roomsLeavingWith(room).map((left) => left.id),
];

String roomExitLabel(Room room, AppLocalizations l10n) {
  if (room.isDirectChat) return l10n.matrixRoomExitDeleteChat;
  if (room.isSpace) return l10n.matrixRoomExitLeaveCommunity;
  return l10n.matrixRoomExitLeaveRoom;
}

String roomExitTitle(Room room, AppLocalizations l10n) {
  if (room.isDirectChat) return l10n.matrixRoomExitDeleteChatTitle;
  if (room.isSpace) return l10n.matrixRoomExitLeaveCommunityTitle;
  return l10n.matrixRoomExitLeaveRoomTitle;
}

String roomExitConfirmLabel(Room room, AppLocalizations l10n) =>
    room.isDirectChat ? l10n.commonDelete : l10n.matrixRoomExitLeave;

Future<String> roomExitMessage(Room room, AppLocalizations l10n) async {
  if (room.isDirectChat) return l10n.matrixRoomExitDirectMessage;
  if (!room.isSpace) {
    return await isLastAdmin(room)
        ? l10n.matrixRoomExitRoomMessageHandOn
        : l10n.matrixRoomExitRoomMessage;
  }
  final rooms = roomsLeavingWith(room);
  final communityToo = await isLastAdmin(room);
  final orphaned = [
    for (final left in rooms)
      if (await isLastAdmin(left)) left,
  ];
  String title(Room left) => roomTitle(left, l10n);
  final count = rooms.length;
  return switch ((rooms, communityToo, orphaned)) {
    ([], false, _) => l10n.matrixRoomExitCommunityNoRooms,
    ([], true, _) => l10n.matrixRoomExitCommunityNoRoomsHandOnCommunity,
    ([final only], false, []) => l10n.matrixRoomExitCommunityOneRoom(
      title(only),
    ),
    ([final only], true, []) =>
      l10n.matrixRoomExitCommunityOneRoomHandOnCommunity(title(only)),
    ([final only], false, [_]) => l10n.matrixRoomExitCommunityOneRoomHandOnRoom(
      title(only),
    ),
    ([final only], true, [_]) =>
      l10n.matrixRoomExitCommunityOneRoomHandOnCommunityAndRoom(title(only)),
    (_, false, []) => l10n.matrixRoomExitCommunityRooms(count),
    (_, true, []) => l10n.matrixRoomExitCommunityRoomsHandOnCommunity(count),
    (_, false, [final only]) => l10n.matrixRoomExitCommunityRoomsHandOnRoom(
      count,
      title(only),
    ),
    (_, true, [final only]) =>
      l10n.matrixRoomExitCommunityRoomsHandOnCommunityAndRoom(
        count,
        title(only),
      ),
    (_, false, _) => l10n.matrixRoomExitCommunityRoomsHandOnRooms(
      count,
      orphaned.length,
    ),
    (_, true, _) => l10n.matrixRoomExitCommunityRoomsHandOnCommunityAndRooms(
      count,
      orphaned.length,
    ),
  };
}

IconData roomExitIcon(Room room) =>
    room.isDirectChat ? Icons.delete_outline : Icons.logout_outlined;

Future<bool> confirmAndExitRoom(
  BuildContext context,
  Room room, {
  required EndCallsIn endCallsIn,
}) async {
  final isDirect = room.isDirectChat;
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final message = await roomExitMessage(room, l10n);
  if (!context.mounted) return false;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(roomExitTitle(room, l10n)),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(roomExitConfirmLabel(room, l10n)),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;

  try {
    await endCallsIn(_roomIdsLeftBy(room));
    await exitRoom(room, isDirect: isDirect);
    return true;
  } catch (e, s) {
    reportCaught('exit room', e, s);
    final String failed;
    if (isDirect) {
      failed = l10n.matrixRoomExitDeleteChatFailed;
    } else if (room.isSpace) {
      failed = l10n.matrixRoomExitLeaveCommunityFailed;
    } else {
      failed = l10n.matrixRoomExitLeaveRoomFailed;
    }
    messenger.showSnackBar(
      SnackBar(content: Text(failureMessage(l10n, e, failed: failed))),
    );
    return false;
  }
}
