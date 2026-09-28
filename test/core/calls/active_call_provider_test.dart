import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import 'package:zuno/core/calls/active_call_marker.dart';
import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/matrixrtc/call_session.dart';
import 'package:zuno/core/calls/models/call_kind.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  late Room room;

  setUp(() {
    room = buildTestRoom(Client('test', database: FakeDatabaseApi()));
    markCallActiveInProcess(false);
  });

  CallSession session() =>
      CallSession.forIncoming(room: room, callId: 'c1', kind: CallKind.voice);

  test('a live call is marked for the whole process', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(activeCallProvider.notifier).set(session());

    expect(isCallActiveInProcess(), isTrue);
  });

  test('ending the call clears the mark', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(activeCallProvider.notifier);

    notifier.set(session());
    notifier.set(null);

    expect(isCallActiveInProcess(), isFalse);
  });

  test('a mark left by an earlier run is dropped on start', () {
    markCallActiveInProcess(true);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(activeCallProvider);

    expect(isCallActiveInProcess(), isFalse);
  });
}
