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

  Event stateEvent(
    String type, {
    String senderId = '@alice:example.org',
    String stateKey = '',
    Map<String, Object?> content = const {},
  }) => buildTestEvent(
    room,
    eventId: r'$1',
    senderId: senderId,
    type: type,
    stateKey: stateKey,
    content: content,
  );

  for (final (name, senderId, membership, description) in [
    ('member join', '@bob:example.org', 'join', 'Bob joined'),
    ('member self-leave', '@bob:example.org', 'leave', 'Bob left'),
    (
      'member removed by someone else (a kick)',
      '@alice:example.org',
      'leave',
      'Alice removed Bob',
    ),
    ('member invite', '@alice:example.org', 'invite', 'Alice invited Bob'),
    ('member ban', '@alice:example.org', 'ban', 'Alice banned Bob'),
    ('member knock', '@bob:example.org', 'knock', 'Bob requested to join'),
    (
      'an unknown membership change still names both sides',
      '@alice:example.org',
      'im.custom',
      "Alice updated Bob's membership",
    ),
  ]) {
    test(name, () {
      final event = stateEvent(
        EventTypes.RoomMember,
        senderId: senderId,
        stateKey: '@bob:example.org',
        content: {'membership': membership},
      );

      expect(describeStateEvent(event), description);
    });
  }

  for (final (name, type, content, description) in [
    (
      'room name changed',
      EventTypes.RoomName,
      {'name': 'New name'},
      'Alice changed the room name to "New name"',
    ),
    (
      'room name removed (empty)',
      EventTypes.RoomName,
      {'name': ''},
      'Alice removed the room name',
    ),
    (
      'room topic changed',
      EventTypes.RoomTopic,
      {'topic': 'New topic'},
      'Alice changed the topic to "New topic"',
    ),
    (
      'room topic removed (missing)',
      EventTypes.RoomTopic,
      <String, Object?>{},
      'Alice removed the room topic',
    ),
  ]) {
    test(name, () {
      expect(
        describeStateEvent(stateEvent(type, content: content)),
        description,
      );
    });
  }

  for (final (type, description) in [
    (EventTypes.RoomAvatar, 'Alice changed the room photo'),
    (EventTypes.RoomCreate, 'Alice created the room'),
    (EventTypes.RoomPowerLevels, 'Alice changed the room permissions'),
    (EventTypes.RoomJoinRules, 'Alice changed who can join the room'),
    (EventTypes.RoomCanonicalAlias, 'Alice changed the room address'),
    (
      EventTypes.HistoryVisibility,
      'Alice changed who can read the room history',
    ),
    (EventTypes.GuestAccess, 'Alice changed guest access'),
    (EventTypes.Encryption, 'Alice turned on encryption'),
    (EventTypes.RoomTombstone, 'Alice upgraded the room'),
  ]) {
    test(type, () {
      expect(describeStateEvent(stateEvent(type)), description);
    });
  }

  test(
    'an unrecognized state event type falls back to null (caller labels it)',
    () {
      expect(describeStateEvent(stateEvent('im.some.custom.state')), isNull);
    },
  );
}
