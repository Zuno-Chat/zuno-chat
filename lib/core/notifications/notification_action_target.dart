import 'package:matrix/matrix.dart';

import '../errors/caught_errors.dart';
import '../push/read_model/opaque_thread_ids.dart';

typedef TimedEvent = ({String id, int ts});

TimedEvent? _newest(Iterable<TimedEvent> events, int boundMs) {
  TimedEvent? newest;
  for (final event in events) {
    if (event.ts > boundMs) continue;
    if (newest == null || event.ts > newest.ts) newest = event;
  }
  return newest;
}

String? newestAtOrBefore(Iterable<TimedEvent> events, int boundMs) =>
    _newest(events, boundMs)?.id;

Future<String?> resolveMarkReadEvent({
  required String? eventId,
  required int? eventSeconds,
  required TimedEvent? lastEvent,
  required Future<List<TimedEvent>> Function() local,
  required Future<TimedEvent?> Function(int boundMs) remote,
}) async {
  if (eventId != null) return eventId;
  if (eventSeconds == null) return lastEvent?.id;
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
}) {
  final last = room.lastEvent;
  return resolveMarkReadEvent(
    eventId: eventId,
    eventSeconds: eventSeconds,
    lastEvent: last == null || !last.eventId.startsWith(r'$')
        ? null
        : (id: last.eventId, ts: last.originServerTs.millisecondsSinceEpoch),
    local: () async => [
      for (final event in await room.client.database.getEventList(
        room,
        limit: 30,
      ))
        if (event.eventId.startsWith(r'$'))
          (id: event.eventId, ts: event.originServerTs.millisecondsSinceEpoch),
    ],
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
