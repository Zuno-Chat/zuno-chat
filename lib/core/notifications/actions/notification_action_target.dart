import 'package:matrix/matrix.dart';

import '../../errors/caught_errors.dart';
import '../../matrix/read_receipts.dart';
import '../../push/nse/opaque_thread_ids.dart';

typedef TimedEvent = ({String id, int ts});

TimedEvent? _newest(Iterable<TimedEvent> events, int boundMs) {
  TimedEvent? newest;
  for (final event in events) {
    if (event.ts > boundMs) continue;
    if (newest == null || event.ts > newest.ts) newest = event;
  }
  return newest;
}

Future<String?> resolveMarkReadEvent({
  required int eventSeconds,
  required TimedEvent? lastEvent,
  required Future<List<TimedEvent>> Function() local,
  required Future<TimedEvent?> Function(int boundMs) remote,
}) async {
  final notifiedSecond = eventSeconds * 1000;
  final bound = notifiedSecond + 999;
  List<TimedEvent> stored;
  try {
    stored = await local();
  } catch (e, s) {
    reportCaught('mark read local events', e, s);
    stored = const [];
  }
  final localPick = _newest([?lastEvent, ...stored], bound);
  if (localPick != null && localPick.ts >= notifiedSecond) return localPick.id;
  TimedEvent? found;
  try {
    found = await remote(bound);
  } catch (e, s) {
    final absent = e is MatrixException && e.error == MatrixError.M_NOT_FOUND;
    if (!absent) reportCaught('mark read remote event', e, s);
    found = null;
  }
  return _newest([?localPick, ?found], bound)?.id;
}

Future<String?> markReadEventIn(
  Room room, {
  String? eventId,
  int? eventSeconds,
}) async {
  if (eventId != null) return eventId;
  if (eventSeconds == null) return newestReadMarkerEventId(room);
  TimedEvent timed(Event event) =>
      (id: event.eventId, ts: event.originServerTs.millisecondsSinceEpoch);
  final last = room.lastEvent;
  return resolveMarkReadEvent(
    eventSeconds: eventSeconds,
    lastEvent: last == null || !canCarryReadMarker(last) ? null : timed(last),
    local: () async => (await storedReadMarkerEvents(room)).map(timed).toList(),
    remote: (bound) async {
      final found = await room.client.getEventByTimestamp(
        room.id,
        bound,
        Direction.b,
      );
      return (id: found.eventId, ts: found.originServerTs);
    },
  );
}

class ThreadKeyRooms {
  ThreadKeyRooms({Future<String?> Function(String roomId)? threadKeyFor})
    : _threadIds = threadKeyFor == null
          ? OpaqueThreadIds.instance
          : OpaqueThreadIds(threadKey: threadKeyFor);

  final OpaqueThreadIds _threadIds;

  Future<Room?> roomFor(Client client, String threadKey) async {
    final roomId = await _threadIds.roomFor(threadKey, [
      for (final room in client.rooms) room.id,
    ]);
    return roomId == null ? null : client.getRoomById(roomId);
  }
}
