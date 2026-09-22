import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/state_event_description.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  late Room room;

  setUp(() {
    room = buildTestRoom(buildTestClient());
    room.setState(User('@alice:example.org', displayName: 'Alice', room: room));
    room.setState(User('@bob:example.org', displayName: 'Bob', room: room));
  });

  test('member join', () {
    final event = buildTestEvent(
      room,
      eventId: r'$1',
      senderId: '@bob:example.org',
      type: EventTypes.RoomMember,
      stateKey: '@bob:example.org',
      content: {'membership': 'join'},
    );
    expect(describeStateEvent(event), 'Bob joined');
  });

  test('member self-leave', () {
    final event = buildTestEvent(
      room,
      eventId: r'$1',
      senderId: '@bob:example.org',
      type: EventTypes.RoomMember,
      stateKey: '@bob:example.org',
      content: {'membership': 'leave'},
    );
    expect(describeStateEvent(event), 'Bob left');
  });

  test('member removed by someone else (a kick)', () {
    final event = buildTestEvent(
      room,
      eventId: r'$1',
      senderId: '@alice:example.org',
      type: EventTypes.RoomMember,
      stateKey: '@bob:example.org',
      content: {'membership': 'leave'},
    );
    expect(describeStateEvent(event), 'Alice removed Bob');
  });

  test('member invite', () {
    final event = buildTestEvent(
      room,
      eventId: r'$1',
      senderId: '@alice:example.org',
      type: EventTypes.RoomMember,
      stateKey: '@bob:example.org',
      content: {'membership': 'invite'},
    );
    expect(describeStateEvent(event), 'Alice invited Bob');
  });

  test('member ban', () {
    final event = buildTestEvent(
      room,
      eventId: r'$1',
      senderId: '@alice:example.org',
      type: EventTypes.RoomMember,
      stateKey: '@bob:example.org',
      content: {'membership': 'ban'},
    );
    expect(describeStateEvent(event), 'Alice banned Bob');
  });

  test('room name changed', () {
    final event = buildTestEvent(
      room,
      eventId: r'$1',
      senderId: '@alice:example.org',
      type: EventTypes.RoomName,
      stateKey: '',
      content: {'name': 'New name'},
    );
    expect(
      describeStateEvent(event),
      'Alice changed the room name to "New name"',
    );
  });

  test('room name removed (empty)', () {
    final event = buildTestEvent(
      room,
      eventId: r'$1',
      senderId: '@alice:example.org',
      type: EventTypes.RoomName,
      stateKey: '',
      content: {'name': ''},
    );
    expect(describeStateEvent(event), 'Alice removed the room name');
  });

  test('room topic changed', () {
    final event = buildTestEvent(
      room,
      eventId: r'$1',
      senderId: '@alice:example.org',
      type: EventTypes.RoomTopic,
      stateKey: '',
      content: {'topic': 'New topic'},
    );
    expect(describeStateEvent(event), 'Alice changed the topic to "New topic"');
  });

  test(
    'an unrecognized state event type falls back to null (caller labels it)',
    () {
      final event = buildTestEvent(
        room,
        eventId: r'$1',
        senderId: '@alice:example.org',
        type: 'im.some.custom.state',
        stateKey: '',
        content: {},
      );
      expect(describeStateEvent(event), isNull);
    },
  );
}
