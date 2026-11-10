import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/calls/matrixrtc/call_removals.dart';
import 'package:zuno/core/calls/matrixrtc/call_removed_event.dart';

import '../../../helpers/call_membership.dart';
import '../../../helpers/fake_matrix.dart';

const _me = '@me:example.org';
const _mod = '@mod:example.org';
const _bob = '@bob:example.org';
const _carol = '@carol:example.org';

void main() {
  late Room room;

  setUp(() {
    room = buildTestRoom(buildTestClient(userId: _me));
    setPowerLevels(room, {
      'users': {_mod: 50},
    });
  });

  test('the event type is Zuno\'s own', () {
    expect(callRemovedEventType, 'im.zuno.call.removed');
  });

  test('the state key is the user ID behind an underscore, since homeservers '
      'refuse a key starting with @ from anyone but that user', () {
    expect(callRemovedStateKey(_bob), '_$_bob');
  });

  group('callRemovals', () {
    test('a state key that is the bare user ID is not a removal', () {
      room.setState(
        buildTestEvent(
          room,
          eventId: r'$removed-bare',
          senderId: _mod,
          type: callRemovedEventType,
          stateKey: _bob,
          content: {'call_id': 'call1'},
        ),
      );

      expect(callRemovals(room, 'call1'), isEmpty);
    });

    test('no removal state means nobody is removed', () {
      expect(callRemovals(room, 'call1'), isEmpty);
    });

    test('a removal by someone who outranks the target names its '
        'moderator', () {
      setCallRemoval(room, _bob, by: _mod);

      expect(callRemovals(room, 'call1'), {_bob: _mod});
    });

    test('a removal by someone without the rank is ignored', () {
      setCallRemoval(room, _bob, by: _carol);

      expect(callRemovals(room, 'call1'), isEmpty);
    });

    test('a removal from another call is stale and ignored', () {
      setCallRemoval(room, _bob, by: _mod, callId: 'call0');

      expect(callRemovals(room, 'call1'), isEmpty);
      expect(callRemovals(room, 'call0'), {_bob: _mod});
    });

    test('a removal naming no call is ignored', () {
      room.setState(
        buildTestEvent(
          room,
          eventId: r'$removed-bad',
          senderId: _mod,
          type: callRemovedEventType,
          stateKey: callRemovedStateKey(_bob),
          content: const {},
        ),
      );

      expect(callRemovals(room, 'call1'), isEmpty);
    });
  });

  group('CallRemovals', () {
    test('a removal seen in the timeline counts while its moderator outranks '
        'the target', () {
      final removals = CallRemovals('call1')
        ..saw(_bob, by: _mod)
        ..saw(_carol, by: _bob);

      expect(removals.current(room), {_bob: _mod});
    });

    test('a removal seen in room state still counts after someone erases '
        'it', () {
      final removals = CallRemovals('call1');
      setCallRemoval(room, _bob, by: _mod);
      expect(removals.current(room), {_bob: _mod});

      room.setState(
        buildTestEvent(
          room,
          eventId: r'$erased',
          senderId: _bob,
          type: callRemovedEventType,
          stateKey: callRemovedStateKey(_bob),
          content: const {},
        ),
      );

      expect(removals.current(room), {_bob: _mod});
    });

    test('removals from room state and from the timeline both count', () {
      setCallRemoval(room, _bob, by: _mod);
      final removals = CallRemovals('call1')..saw(_carol, by: _mod);

      expect(removals.current(room), {_bob: _mod, _carol: _mod});
    });
  });

  group('currentCallJoins', () {
    void member(String userId, String membership) => room.setState(
      StrippedStateEvent(
        type: EventTypes.RoomMember,
        senderId: userId,
        stateKey: userId,
        content: {'membership': membership},
      ),
    );

    test('leaves out removed users and users who are out of the room', () {
      for (final (userId, deviceId) in [
        (_bob, 'BOB'),
        (_carol, 'CAROL'),
        (_mod, 'MOD'),
        (_me, 'ME'),
      ]) {
        joinCall(room, userId: userId, deviceId: deviceId, callId: 'call1');
      }
      member(_carol, 'leave');
      member(_mod, 'join');

      final joins = currentCallJoins(room, 'call1', {_bob: _mod});

      expect([
        for (final join in joins) join.userId,
      ], unorderedEquals([_mod, _me]));
    });
  });
}
