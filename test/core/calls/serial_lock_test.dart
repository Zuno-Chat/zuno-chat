import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/calls/serial_lock.dart';

void main() {
  test('an idle lock runs the next action in the caller\'s own zone, so a '
      'fake clock in a later test can still drive it', () async {
    final lock = SerialLock();
    await lock.run(() async {});

    fakeAsync((async) {
      var ran = false;
      unawaited(lock.run(() async => ran = true));
      async.flushMicrotasks();

      expect(ran, isTrue);
    });
  });

  test('forgetting every lock frees one jammed by an action that never '
      'finished', () async {
    final lock = SerialLock();
    unawaited(lock.run(() => Completer<void>().future));

    KeyedSerialLock.forgetAllForTest();

    expect(await lock.run(() async => 'ran'), 'ran');
  });

  group('KeyedSerialLock', () {
    test('serializes actions for the same key', () async {
      final lock = KeyedSerialLock();
      final gate = Completer<void>();
      final order = <String>[];

      final a = lock.run('room', () async {
        await gate.future;
        order.add('a');
      });
      final b = lock.run('room', () async => order.add('b'));
      await pumpEventQueue();
      expect(order, isEmpty);

      gate.complete();
      await Future.wait([a, b]);
      expect(order, ['a', 'b']);
    });

    test('lets different keys run side by side', () async {
      final lock = KeyedSerialLock();
      final gate = Completer<void>();
      final order = <String>[];

      final a = lock.run('room-a', () async {
        await gate.future;
        order.add('a');
      });
      await lock.run('room-b', () async => order.add('b'));

      expect(order, ['b']);
      gate.complete();
      await a;
      expect(order, ['b', 'a']);
    });

    test('a failure for one key does not block that key afterwards', () async {
      final lock = KeyedSerialLock();

      final failing = lock.run<void>('room', () async => throw StateError('x'));
      final next = lock.run('room', () async => 'ran');

      await expectLater(failing, throwsStateError);
      expect(await next, 'ran');
    });
  });
}
