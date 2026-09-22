import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/features/chat/data/sync_filter.dart';

const roomId = '!room:example.org';

void main() {
  test('a joined entry for the room touches it', () {
    final update = SyncUpdate(
      nextBatch: 's1',
      rooms: RoomsUpdate(join: {roomId: JoinedRoomUpdate()}),
    );
    expect(syncTouchesRoom(update, roomId), isTrue);
  });

  test('an invited entry for the room touches it', () {
    final update = SyncUpdate(
      nextBatch: 's1',
      rooms: RoomsUpdate(invite: {roomId: InvitedRoomUpdate()}),
    );
    expect(syncTouchesRoom(update, roomId), isTrue);
  });

  test('a left entry for the room touches it', () {
    final update = SyncUpdate(
      nextBatch: 's1',
      rooms: RoomsUpdate(leave: {roomId: LeftRoomUpdate()}),
    );
    expect(syncTouchesRoom(update, roomId), isTrue);
  });

  test('another room or no rooms does not', () {
    expect(syncTouchesRoom(SyncUpdate(nextBatch: 's1'), roomId), isFalse);
    final other = SyncUpdate(
      nextBatch: 's1',
      rooms: RoomsUpdate(join: {'!other:example.org': JoinedRoomUpdate()}),
    );
    expect(syncTouchesRoom(other, roomId), isFalse);
  });
}
