import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

Future<void> exitRoom(Room room, {required bool isDirect}) async {
  if (room.membership != Membership.leave) await room.leave();
  if (!isDirect) return;
  try {
    await room.forget();
  } catch (_) {}
}

String roomExitLabel(Room room) =>
    room.isDirectChat ? 'Delete chat' : 'Leave room';

String roomExitTitle(Room room) => '${roomExitLabel(room)}?';

String roomExitConfirmLabel(Room room) =>
    room.isDirectChat ? 'Delete' : 'Leave';

String roomExitMessage(Room room) => room.isDirectChat
    ? 'This chat and its messages leave this device. Nobody can undo this.'
    : 'You will stop getting messages here.';

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
    messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    return false;
  }
}
