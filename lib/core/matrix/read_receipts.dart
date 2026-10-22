import 'package:matrix/matrix.dart';

bool canCarryReadMarker(Event event) =>
    event.status.isSent && event.eventId.startsWith(r'$');

Future<Iterable<Event>> storedReadMarkerEvents(Room room) async =>
    (await room.client.database.getEventList(
      room,
      limit: 30,
    )).where(canCarryReadMarker);

Future<String?> newestReadMarkerEventId(Room room) async {
  final last = room.lastEvent;
  if (last != null && canCarryReadMarker(last)) return last.eventId;
  return (await storedReadMarkerEvents(room)).firstOrNull?.eventId;
}

Future<void> markRoomRead(Room room, String eventId) =>
    room.setReadMarker(eventId, mRead: eventId);

bool isReadByOthers(Room room, Event event) {
  final ts = event.originServerTs.millisecondsSinceEpoch;
  return room.receiptState.global.otherUsers.values.any(
    (receipt) => receipt.ts >= ts,
  );
}

List<({User user, DateTime at})> seenByOthers(Room room, Event event) {
  final ts = event.originServerTs.millisecondsSinceEpoch;
  return room.receiptState.global.otherUsers.entries
      .where((entry) => entry.value.ts >= ts)
      .map(
        (entry) => (
          user: room.unsafeGetUserFromMemoryOrFallback(entry.key),
          at: entry.value.timestamp,
        ),
      )
      .toList()
    ..sort((a, b) => a.at.compareTo(b.at));
}
