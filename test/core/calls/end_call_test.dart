import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/end_call.dart';
import 'package:zuno/core/calls/models/call_kind.dart';

import '../../helpers/fake_call_session.dart';
import '../../helpers/fake_matrix.dart';

class _StuckCall extends FakeCallSession {
  _StuckCall({required super.room}) : super(kind: CallKind.voice);

  @override
  Future<void> hangUp({bool byUser = false, bool summarized = false}) =>
      Completer<void>().future;
}

void main() {
  late Client client;

  setUp(() => client = buildTestClient(userId: '@me:example.org'));

  ProviderContainer containerWith(FakeCallSession? call) {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    if (call != null) container.read(activeCallProvider.notifier).set(call);
    return container;
  }

  test('ends the active call, as the user\'s own choice, when its room is '
      'among those being left', () async {
    final call = FakeCallSession(
      room: buildTestRoom(client, id: '!hike:x'),
      kind: CallKind.voice,
    );
    final container = containerWith(call);

    await container.read(endCallsInProvider)(['!other:x', '!hike:x']);

    expect(call.hangUpsByUser, [true]);
  });

  test('leaves a call in another room alone', () async {
    final call = FakeCallSession(
      room: buildTestRoom(client, id: '!hike:x'),
      kind: CallKind.voice,
    );
    final container = containerWith(call);

    await container.read(endCallsInProvider)(['!other:x']);

    expect(call.hangUps, 0);
  });

  test('reads the call when it runs, not when it was handed out', () async {
    final container = containerWith(null);
    final endCallsIn = container.read(endCallsInProvider);
    final call = FakeCallSession(
      room: buildTestRoom(client, id: '!hike:x'),
      kind: CallKind.voice,
    );
    container.read(activeCallProvider.notifier).set(call);

    await endCallsIn(['!hike:x']);

    expect(call.hangUpsByUser, [true]);
  });

  testWidgets('a call that never finishes ending does not hold up the leave', (
    tester,
  ) async {
    var done = false;
    unawaited(
      endCall(_StuckCall(room: buildTestRoom(client, id: '!hike:x')))
          .then((_) => done = true),
    );

    await tester.pump(const Duration(seconds: 6));

    expect(done, isTrue);
  });
}
