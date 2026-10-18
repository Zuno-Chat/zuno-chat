import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/l10n/l10n.dart';
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
    Map<String, Object?>? prevContent,
  }) => buildTestEvent(
    room,
    eventId: r'$1',
    senderId: senderId,
    type: type,
    stateKey: stateKey,
    content: content,
    prevContent: prevContent,
  );

  String? describe(Event event) =>
      describeStateEvent(englishLocalizations, event);

  for (final (name, senderId, was, membership, description) in [
    ('member join', '@bob:example.org', null, 'join', 'Bob joined'),
    ('member self-leave', '@bob:example.org', 'join', 'leave', 'Bob left'),
    (
      'member removed by someone else (a kick)',
      '@alice:example.org',
      'join',
      'leave',
      'Alice removed Bob',
    ),
    (
      'member invite',
      '@alice:example.org',
      null,
      'invite',
      'Alice invited Bob',
    ),
    ('member ban', '@alice:example.org', 'join', 'ban', 'Alice banned Bob'),
    ('member knock', '@bob:example.org', null, 'knock', 'Bob asked to join'),
    (
      'a membership change with nothing to say falls back to null',
      '@alice:example.org',
      'join',
      'join',
      null,
    ),
  ]) {
    test(name, () {
      final event = stateEvent(
        EventTypes.RoomMember,
        senderId: senderId,
        stateKey: '@bob:example.org',
        content: {'membership': membership},
        prevContent: was == null ? null : {'membership': was},
      );

      expect(describe(event), description);
    });
  }

  test('a role change names the new role', () {
    final event = stateEvent(
      EventTypes.RoomPowerLevels,
      content: {
        'users': {'@bob:example.org': 100},
      },
      prevContent: {'users': <String, Object?>{}},
    );

    expect(describe(event), 'Alice made Bob an admin');
  });

  test('a deleted state event falls back to null', () {
    final event = stateEvent(EventTypes.RoomName, content: {'name': 'X'});
    event.unsigned = {
      'redacted_because': {
        'event_id': r'$r',
        'type': EventTypes.Redaction,
        'sender': '@alice:example.org',
        'origin_server_ts': 0,
        'content': <String, Object?>{},
      },
    };

    expect(describe(event), isNull);
  });

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
      'Alice changed the room topic',
    ),
    (
      'room topic removed (missing)',
      EventTypes.RoomTopic,
      <String, Object?>{},
      'Alice removed the room topic',
    ),
  ]) {
    test(name, () {
      expect(describe(stateEvent(type, content: content)), description);
    });
  }

  for (final (type, description) in [
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
      expect(describe(stateEvent(type)), description);
    });
  }

  test('room photo changed and removed', () {
    expect(
      describe(
        stateEvent(EventTypes.RoomAvatar, content: {'url': 'mxc://x/a'}),
      ),
      'Alice changed the room photo',
    );
    expect(
      describe(stateEvent(EventTypes.RoomAvatar)),
      'Alice removed the room photo',
    );
  });

  test(
    'an unrecognized state event type falls back to null (caller labels it)',
    () {
      expect(describe(stateEvent('im.some.custom.state')), isNull);
    },
  );
}
