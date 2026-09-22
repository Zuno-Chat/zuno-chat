import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/calls/cloudflare/negotiation_lock.dart';

void main() {
  test('runs a single action and returns its result', () async {
    final lock = NegotiationLock();
    final result = await lock.run(() async => 42);
    expect(result, 42);
  });

  test('serializes overlapping calls — the second never starts until the first finishes', () async {
    final lock = NegotiationLock();
    final order = <String>[];
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();

    final first = lock.run(() async {
      order.add('first-start');
      firstStarted.complete();
      await releaseFirst.future;
      order.add('first-end');
    });
    await firstStarted.future;
    final second = lock.run(() async {
      order.add('second-start');
      order.add('second-end');
    });

    expect(order, ['first-start']);

    releaseFirst.complete();
    await first;
    await second;

    expect(order, ['first-start', 'first-end', 'second-start', 'second-end']);
  });

  test(
    'a failed action does not jam the queue for what comes after it',
    () async {
      final lock = NegotiationLock();
      await expectLater(
        lock.run(() async => throw StateError('negotiation rejected')),
        throwsA(isA<StateError>()),
      );
      final result = await lock.run(() async => 'still works');
      expect(result, 'still works');
    },
  );

  test(
    'runs three queued actions in call order, not completion order',
    () async {
      final lock = NegotiationLock();
      final order = <int>[];
      final futures = [
        lock.run(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          order.add(1);
        }),
        lock.run(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          order.add(2);
        }),
        lock.run(() async {
          order.add(3);
        }),
      ];
      await Future.wait(futures);
      expect(order, [1, 2, 3]);
    },
  );
}
