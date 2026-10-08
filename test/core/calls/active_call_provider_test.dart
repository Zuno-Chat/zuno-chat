import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import 'package:zuno/core/calls/active_call_marker.dart';
import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/matrixrtc/call_session.dart';
import 'package:zuno/core/calls/models/call_kind.dart';

import '../../helpers/fake_call_session.dart';
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

  test('clearing the call that is live ends it', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(activeCallProvider.notifier);
    final live = session();
    notifier.set(live);

    notifier.clear(live);

    expect(container.read(activeCallProvider), isNull);
    expect(isCallActiveInProcess(), isFalse);
  });

  test(
    'clearing a call that is no longer live leaves the newer call alone',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(activeCallProvider.notifier);
      final ended = session();
      final newer = session();
      notifier.set(newer);

      notifier.clear(ended);

      expect(container.read(activeCallProvider), same(newer));
      expect(isCallActiveInProcess(), isTrue);
    },
  );

  group('starting a call', () {
    test('a live call refuses another, which is never built', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(activeCallProvider.notifier);
      final live = session();
      expect(notifier.start(() => live), same(live));

      var built = false;
      final refused = notifier.start(() {
        built = true;
        return session();
      });

      expect(refused, isNull);
      expect(built, isFalse);
      expect(container.read(activeCallProvider), same(live));
    });

    test('a call that has ended no longer holds the line', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(activeCallProvider.notifier);
      notifier.start(
        () => FakeCallSession(room: room, kind: CallKind.voice)..end(),
      );
      final next = session();

      expect(notifier.start(() => next), same(next));
      expect(isCallActiveInProcess(), isTrue);
    });

    test('a cleared call lets the next one start', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(activeCallProvider.notifier);
      final first = session();
      notifier.start(() => first);
      notifier.clear(first);
      final next = session();

      expect(notifier.start(() => next), same(next));
    });
  });

  test('a mark left by an earlier run is dropped on start', () {
    markCallActiveInProcess(true);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(activeCallProvider);

    expect(isCallActiveInProcess(), isFalse);
  });
}
