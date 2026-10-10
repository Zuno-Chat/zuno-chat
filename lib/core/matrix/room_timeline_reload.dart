import 'dart:convert';

import 'package:matrix/matrix.dart';

import 'sync_coordinator.dart';

bool canReloadRoomTimeline(Room room) => room.membership == Membership.join;

Future<void> reloadRoomTimeline(Room room, {required SyncCoordinator? sync}) {
  Future<void> reload() => _replaceWithLatestPage(room);
  return sync?.whileIdle(reload) ?? reload();
}

Future<void> _replaceWithLatestPage(Room room) async {
  if (!canReloadRoomTimeline(room)) {
    throw StateError('Only a joined room reloads its messages');
  }
  final client = room.client;
  final latest = await client.getRoomEvents(
    room.id,
    Direction.b,
    limit: Room.defaultHistoryCount,
    filter: jsonEncode(StateFilter(lazyLoadMembers: true).toJson()),
  );
  await client.database.transaction(() async {
    await client.database.deleteTimelineForRoom(room.id);
    room.prev_batch = latest.end;
    await client.database.setRoomPrevBatch(latest.end, room.id, client);
    await client.handleSync(
      SyncUpdate(
        nextBatch: '',
        rooms: RoomsUpdate(
          join: {
            room.id: JoinedRoomUpdate(
              state: latest.state,
              timeline: TimelineUpdate(
                limited: false,
                events: latest.chunk,
                prevBatch: latest.end,
              ),
            ),
          },
        ),
      ),
      direction: Direction.b,
    );
  });
}
