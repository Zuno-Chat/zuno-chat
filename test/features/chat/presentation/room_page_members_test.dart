import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import '../../../helpers/fake_matrix.dart';
import 'room_page_harness.dart';

class _StoredMembersDb extends StoredEventsFakeDatabaseApi {
  int memberLoads = 0;

  @override
  Future<List<User>> getUsers(Room room) async {
    if (memberLoads++ >= 3) return [];
    return [
      User('@me:example.org', membership: 'join', room: room),
      User('@bob:example.org', membership: 'join', room: room),
    ];
  }

  @override
  Future<List<Event>> getUnimportantRoomEventStatesForRoom(
    List<String> events,
    Room room,
  ) async => [];
}

void main() {
  testWidgets('opening a room loads no members', (tester) async {
    final db = _StoredMembersDb();
    final harness = RoomPageHarness(db: db);
    harness.room.partial = true;

    await harness.pumpRoomPage(tester);
    await harness.settle(tester);

    expect(db.memberLoads, 0);
  });
}
