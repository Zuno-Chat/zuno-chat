import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../errors/best_effort.dart';
import '../errors/connection_error.dart';
import 'communities.dart';
import 'room_title.dart';

Future<void> exitRoom(Room room, {required bool isDirect}) async {
  if (room.isSpace) return leaveCommunity(room);
  if (room.membership != Membership.leave) await room.leave();
  if (!isDirect) return;
  try {
    await room.forget();
  } catch (_) {}
}

String roomExitLabel(Room room) {
  if (room.isDirectChat) return 'Delete chat';
  if (room.isSpace) return 'Leave community';
  return 'Leave room';
}

String roomExitTitle(Room room) => '${roomExitLabel(room)}?';

String roomExitConfirmLabel(Room room) =>
    room.isDirectChat ? 'Delete' : 'Leave';

String roomExitMessage(Room room) {
  if (room.isDirectChat) {
    return 'This chat and its messages leave this device. Nobody can undo this.';
  }
  if (!room.isSpace) return 'You will stop getting messages here.';
  final rooms = roomsLeavingWith(room);
  return switch (rooms.length) {
    0 => 'You will stop seeing its rooms.',
    1 => 'You also leave ${roomTitle(rooms.single)}.',
    final count => 'You also leave $count of its rooms.',
  };
}

IconData roomExitIcon(Room room) =>
    room.isDirectChat ? Icons.delete_outline : Icons.logout_outlined;

Future<bool> confirmAndExitRoom(BuildContext context, Room room) async {
  final isDirect = room.isDirectChat;
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(roomExitTitle(room)),
      content: Text(roomExitMessage(room)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(roomExitConfirmLabel(room)),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;

  try {
    await exitRoom(room, isDirect: isDirect);
    return true;
  } catch (e) {
    logCaught('exit room', e);
    final String failed;
    if (isDirect) {
      failed = 'Could not delete the chat.';
    } else if (room.isSpace) {
      failed = 'Could not leave the community.';
    } else {
      failed = 'Could not leave the room.';
    }
    messenger.showSnackBar(
      SnackBar(content: Text(failureMessage(e, failed: failed))),
    );
    return false;
  }
}
