import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/optimistic_room_state.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  late Room room;

  setUp(() => room = buildTestRoom(buildTestClient(userId: '@me:example.org')));

  test('makes the new content immediately readable via room.getState', () {
    expect(room.getState(EventTypes.RoomTopic), isNull);

    applyOptimisticRoomState(room, EventTypes.RoomTopic, {
      'topic': 'New topic',
    });

    expect(room.getState(EventTypes.RoomTopic)?.content['topic'], 'New topic');
    expect(room.topic, 'New topic');
  });

  test('writes under the given state key, as the signed-in user', () {
    applyOptimisticRoomState(room, EventTypes.RoomMember, {
      'membership': 'invite',
    }, stateKey: '@bob:example.org');

    final member = room.getState(EventTypes.RoomMember, '@bob:example.org');
    expect(member?.content['membership'], 'invite');
    expect(member?.senderId, '@me:example.org');
    expect(room.getState(EventTypes.RoomMember), isNull);
  });
}
