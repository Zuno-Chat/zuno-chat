import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/room_user_display.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  late Client client;
  late Room room;

  setUp(() {
    client = buildTestClient(userId: '@me:example.org');
    room = buildTestRoom(client);
  });

  void addMember(String userId, String displayName) {
    room.setState(
      Event(
        eventId: '\$member-$userId',
        type: EventTypes.RoomMember,
        stateKey: userId,
        senderId: userId,
        originServerTs: DateTime.now(),
        content: {'membership': 'join', 'displayname': displayName},
        room: room,
      ),
    );
  }

  test('returns the display name for a member already in memory', () async {
    room.partial = false;
    addMember('@alice:example.org', 'Alice');

    final user = await resolveRoomUser(room, '@alice:example.org');

    expect(user.calcDisplayname(), 'Alice');
  });

  test('falls back to the localpart for an unknown member', () async {
    room.partial = false;

    final user = await resolveRoomUser(room, '@bob:example.org');

    expect(user.calcDisplayname(), 'Bob');
  });

  test('falls back to memory when the database lookup throws', () async {
    expect(room.partial, isTrue);
    addMember('@alice:example.org', 'Alice');

    final user = await resolveRoomUser(room, '@alice:example.org');

    expect(user.calcDisplayname(), 'Alice');
  });

  test('stays local when network is not allowed', () async {
    room.partial = false;

    final user = await resolveRoomUser(room, '@carol:example.org');

    expect(user.id, '@carol:example.org');
  });
}
