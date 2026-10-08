import 'package:matrix/matrix.dart';

import '../matrix/room_title.dart';
import 'live_location_capture.dart';

LiveLocationNotice liveLocationNotice(
  List<({Room room, DateTime endsAt})> shares,
) {
  final endsAt = shares
      .map((entry) => entry.endsAt)
      .reduce((a, b) => a.isAfter(b) ? a : b);
  if (shares case [final only]) {
    final title = roomTitle(only.room);
    return LiveLocationNotice(
      title: 'Sharing live location',
      text: only.room.isDirectChat ? 'With $title' : 'In $title',
      endsAt: endsAt,
      roomId: only.room.id,
    );
  }
  final chats = shares.where((entry) => entry.room.isDirectChat).length;
  final rooms = shares.length - chats;
  final parts = [
    if (chats > 0) _counted(chats, 'chat'),
    if (rooms > 0) _counted(rooms, 'room'),
  ];
  return LiveLocationNotice(
    title: 'Sharing live location',
    text: 'In ${parts.join(' and ')}',
    endsAt: endsAt,
  );
}

String _counted(int count, String noun) =>
    '$count $noun${count == 1 ? '' : 's'}';
