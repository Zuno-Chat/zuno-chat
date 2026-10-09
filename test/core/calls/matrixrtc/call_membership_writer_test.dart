import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/matrixrtc/call_member_state.dart';
import 'package:zuno/core/calls/matrixrtc/call_membership_writer.dart';

import '../../../helpers/fake_matrix.dart';

typedef _Write = ({
  String roomId,
  String eventType,
  String stateKey,
  Map<String, Object?> body,
  Completer<String> answer,
});

class _StateClient extends Client {
  _StateClient() : super('test', database: FakeDatabaseApi()) {
    setUserId('@me:example.org');
  }

  final writes = <_Write>[];

  List<Map<String, Object?>> bodiesFor(String roomId) => [
    for (final write in writes)
      if (write.roomId == roomId) write.body,
  ];

  @override
  Future<String> setRoomStateWithKey(
    String roomId,
    String eventType,
    String stateKey,
    Map<String, Object?> body,
  ) {
    final answer = Completer<String>();
    writes.add((
      roomId: roomId,
      eventType: eventType,
      stateKey: stateKey,
      body: body,
      answer: answer,
    ));
    return answer.future;
  }
}

Map<String, Object?> _membership(String callId) => {
  'memberships': [
    {'call_id': callId},
  ],
};

final _cleared = <String, Object?>{'memberships': <Object?>[]};

void main() {
  test('writes our own call membership for the room', () {
    fakeAsync((async) {
      final client = _StateClient();

      String? eventId;
      writeOwnCallMembership(
        client,
        '!a:x',
        _membership('c1'),
      ).then((id) => eventId = id);
      async.flushMicrotasks();
      client.writes.single.answer.complete(r'$e1');
      async.flushMicrotasks();

      final write = client.writes.single;
      expect(write.eventType, callMemberEventType);
      expect(write.stateKey, '@me:example.org');
      expect(write.body, _membership('c1'));
      expect(eventId, r'$e1');
    });
  });

  test('writes for one room go out one at a time, in the order asked', () {
    fakeAsync((async) {
      final client = _StateClient();

      writeOwnCallMembership(client, '!a:x', _cleared);
      writeOwnCallMembership(client, '!a:x', _membership('c2'));
      async.flushMicrotasks();
      expect(client.bodiesFor('!a:x'), [_cleared]);

      client.writes.first.answer.complete(r'$e1');
      async.flushMicrotasks();

      expect(client.bodiesFor('!a:x'), [_cleared, _membership('c2')]);
    });
  });

  test('writes for different rooms do not wait for each other', () {
    fakeAsync((async) {
      final client = _StateClient();

      writeOwnCallMembership(client, '!a:x', _cleared);
      writeOwnCallMembership(client, '!b:x', _membership('c2'));
      async.flushMicrotasks();

      expect(client.writes.map((w) => w.roomId), ['!a:x', '!b:x']);
    });
  });

  test('a failed write lets the next one go, and its caller hears why', () {
    fakeAsync((async) {
      final client = _StateClient();

      Object? failure;
      writeOwnCallMembership(client, '!a:x', _cleared).catchError((Object e) {
        failure = e;
        return '';
      });
      writeOwnCallMembership(client, '!a:x', _membership('c2'));
      async.flushMicrotasks();
      client.writes.first.answer.completeError(StateError('refused'));
      async.flushMicrotasks();

      expect(failure, isA<StateError>());
      expect(client.bodiesFor('!a:x'), [_cleared, _membership('c2')]);
    });
  });

  test('a write that hangs lets the next one go after a few seconds, and '
      'the newest membership is written again once the stale one lands', () {
    fakeAsync((async) {
      final client = _StateClient();

      writeOwnCallMembership(client, '!a:x', _cleared);
      writeOwnCallMembership(client, '!a:x', _membership('c2'));
      async.elapse(const Duration(seconds: 4));
      expect(client.bodiesFor('!a:x'), [_cleared]);

      async.elapse(const Duration(seconds: 1));
      expect(client.bodiesFor('!a:x'), [_cleared, _membership('c2')]);
      client.writes[1].answer.complete(r'$e2');
      async.flushMicrotasks();

      client.writes.first.answer.complete(r'$e1');
      async.flushMicrotasks();

      expect(client.bodiesFor('!a:x'), [
        _cleared,
        _membership('c2'),
        _membership('c2'),
      ]);
    });
  });

  test('a stale write that fails late is followed by the newest membership '
      'too', () {
    fakeAsync((async) {
      final client = _StateClient();

      writeOwnCallMembership(
        client,
        '!a:x',
        _cleared,
      ).catchError((Object _) => '');
      writeOwnCallMembership(client, '!a:x', _membership('c2'));
      async.elapse(const Duration(seconds: 5));
      client.writes[1].answer.complete(r'$e2');
      async.flushMicrotasks();

      client.writes.first.answer.completeError(StateError('timed out'));
      async.flushMicrotasks();

      expect(client.bodiesFor('!a:x').last, _membership('c2'));
      expect(client.bodiesFor('!a:x'), hasLength(3));
    });
  });

  test('a write that hangs but is still the newest is not written again', () {
    fakeAsync((async) {
      final client = _StateClient();

      writeOwnCallMembership(client, '!a:x', _cleared);
      async.elapse(const Duration(seconds: 6));
      client.writes.single.answer.complete(r'$e1');
      async.flushMicrotasks();

      expect(client.bodiesFor('!a:x'), [_cleared]);
    });
  });
}
