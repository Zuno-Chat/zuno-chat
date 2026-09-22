import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/optimistic_room_state.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  test('makes the new content immediately readable via room.getState', () {
    final client = buildTestClient(userId: '@me:example.org');
    final room = buildTestRoom(client);

    expect(room.getState(EventTypes.RoomTopic), isNull);

    applyOptimisticRoomState(room, EventTypes.RoomTopic, {
      'topic': 'New topic',
    });

    expect(room.getState(EventTypes.RoomTopic)?.content['topic'], 'New topic');
    expect(room.topic, 'New topic');
  });

  test('overwrites a previous value for the same type/stateKey', () {
    final client = buildTestClient(userId: '@me:example.org');
    final room = buildTestRoom(client);
    applyOptimisticRoomState(room, EventTypes.RoomName, {'name': 'Old'});

    applyOptimisticRoomState(room, EventTypes.RoomName, {'name': 'New'});

    expect(room.name, 'New');
  });

  test('respects a non-default stateKey (e.g. m.room.power_levels)', () {
    final client = buildTestClient(userId: '@admin:example.org');
    final room = buildTestRoom(client);

    applyOptimisticRoomState(room, EventTypes.RoomPowerLevels, {
      'events_default': 50,
    });

    expect(
      room.getState(EventTypes.RoomPowerLevels)?.content['events_default'],
      50,
    );
  });
}
