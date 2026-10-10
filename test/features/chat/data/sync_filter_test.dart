import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/features/chat/data/sync_filter.dart';

const roomId = '!room:example.org';

void main() {
  for (final (membership, rooms) in [
    ('joined', RoomsUpdate(join: {roomId: JoinedRoomUpdate()})),
    ('invited', RoomsUpdate(invite: {roomId: InvitedRoomUpdate()})),
    ('left', RoomsUpdate(leave: {roomId: LeftRoomUpdate()})),
  ]) {
    test('a $membership entry for the room touches it', () {
      final update = SyncUpdate(nextBatch: 's1', rooms: rooms);
      expect(syncTouchesRoom(update, roomId), isTrue);
    });
  }

  test('another room or no rooms does not', () {
    expect(syncTouchesRoom(SyncUpdate(nextBatch: 's1'), roomId), isFalse);
    final other = SyncUpdate(
      nextBatch: 's1',
      rooms: RoomsUpdate(join: {'!other:example.org': JoinedRoomUpdate()}),
    );
    expect(syncTouchesRoom(other, roomId), isFalse);
  });
}
