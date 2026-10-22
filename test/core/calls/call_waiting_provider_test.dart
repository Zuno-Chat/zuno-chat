import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/call_waiting_provider.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/platform/system_ring.dart';

import '../../helpers/fake_call_session.dart';
import '../../helpers/fake_matrix.dart';

void main() {
  late Room room;
  late ProviderContainer container;

  setUp(() {
    room = buildTestRoom(Client('test', database: FakeDatabaseApi()));
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  FakeCallSession onACall() {
    final call = FakeCallSession(room: room, kind: CallKind.voice);
    container.read(activeCallProvider.notifier).set(call);
    return call;
  }

  void ring(String callId) =>
      SystemRing.instance.set(roomId: room.id, callId: callId);

  String? waiting() => container.read(callWaitingProvider);

  test('a ring for another call while on a call is waiting', () async {
    onACall();
    ring('call2');
    await pumpEventQueue();

    expect(waiting(), 'call2');
  });

  test('a ring with no call held is a normal ring', () {
    ring('call2');

    expect(waiting(), isNull);
  });

  test('the call on the line ringing is not waiting on itself', () {
    final call = onACall();
    ring(call.callId);

    expect(waiting(), isNull);
  });

  test('a waiting ring turns normal once the call on the line ends', () async {
    final call = onACall();
    ring('call2');
    await pumpEventQueue();
    final seen = <String?>[];
    container.listen(callWaitingProvider, (_, next) => seen.add(next));

    call.end();
    await pumpEventQueue();

    expect(seen, [null]);
    expect(waiting(), isNull);
  });

  test('no ring, nothing waits', () async {
    onACall();
    ring('call2');
    await pumpEventQueue();

    SystemRing.instance.clear('call2');
    await pumpEventQueue();

    expect(waiting(), isNull);
  });

  test('a ring that starts while on a call is waiting once the moment\'s '
      'work is done, never mid-build', () async {
    onACall();
    expect(waiting(), isNull);

    ring('call2');
    expect(waiting(), isNull);
    await pumpEventQueue();

    expect(waiting(), 'call2');
  });

  test('the rule itself answers at once', () {
    final call = onACall();

    expect(waitingRing(call, 'call2'), 'call2');
    expect(waitingRing(call, call.callId), isNull);
    expect(waitingRing(null, 'call2'), isNull);
    expect(waitingRing(call..end(), 'call2'), isNull);
  });

  test('a call taking the line tells its listeners at once', () {
    final seen = <String?>[];
    container.listen(callWaitingProvider, (_, next) => seen.add(next));
    ring('call2');

    onACall();

    expect(seen, ['call2']);
  });
}
