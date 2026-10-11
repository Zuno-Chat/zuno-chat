import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../calls/end_call.dart';
import '../errors/caught_errors.dart';
import '../errors/connection_error.dart';
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

String roomExitLabel(Room room) {
  if (room.isDirectChat) return 'Delete chat';
  if (room.isSpace) return 'Leave community';
  return 'Leave room';
}

String roomExitTitle(Room room) => '${roomExitLabel(room)}?';

String roomExitConfirmLabel(Room room) =>
    room.isDirectChat ? 'Delete' : 'Leave';

Future<String> roomExitMessage(Room room) async {
  if (room.isDirectChat) {
    return 'This chat and its messages leave this device. Nobody can undo this.';
  }
  if (!room.isSpace) {
    const leaving = 'You will stop getting messages here.';
    if (!await isLastAdmin(room)) return leaving;
    return '$leaving ${_handOnFirst('this room', 1)}';
  }
  final rooms = roomsLeavingWith(room);
  final leaving = switch (rooms.length) {
    0 => 'You will stop seeing its rooms.',
    1 => 'You also leave ${roomTitle(rooms.single)}.',
    final count => 'You also leave $count of its rooms.',
  };
  final communityOrphaned = await isLastAdmin(room);
  final orphaned = [
    for (final left in rooms)
      if (await isLastAdmin(left)) left,
  ];
  final targets = [
    if (communityOrphaned) 'this community',
    if (orphaned case [final only])
      roomTitle(only)
    else if (orphaned.isNotEmpty)
      '${orphaned.length} of its rooms',
  ];
  if (targets.isEmpty) return leaving;
  final count = orphaned.length + (communityOrphaned ? 1 : 0);
  return '$leaving ${_handOnFirst(targets.join(' and '), count)}';
}

String _handOnFirst(String target, int count) =>
    'Make someone else an admin of $target first, or nobody can manage '
    '${count == 1 ? 'it' : 'them'} again.';

IconData roomExitIcon(Room room) =>
    room.isDirectChat ? Icons.delete_outline : Icons.logout_outlined;

Future<bool> confirmAndExitRoom(
  BuildContext context,
  Room room, {
  required EndCallsIn endCallsIn,
}) async {
  final isDirect = room.isDirectChat;
  final messenger = ScaffoldMessenger.of(context);
  final message = await roomExitMessage(room);
  if (!context.mounted) return false;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(roomExitTitle(room)),
      content: Text(message),
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
    await endCallsIn(_roomIdsLeftBy(room));
    await exitRoom(room, isDirect: isDirect);
    return true;
  } catch (e, s) {
    reportCaught('exit room', e, s);
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
