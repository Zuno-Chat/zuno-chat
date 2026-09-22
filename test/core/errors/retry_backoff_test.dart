import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/errors/retry_backoff.dart';

void main() {
  test('returns the value on the first successful attempt, no delay', () {
    fakeAsync((async) {
      var calls = 0;
      String? result;
      retryWithBackoff(() async {
        calls++;
        return 'ok';
      }, label: 'test').then((r) => result = r);

      async.flushMicrotasks();

      expect(calls, 1);
      expect(result, 'ok');
    });
  });

  test('retries with growing delays and returns once it succeeds', () {
    fakeAsync((async) {
      var calls = 0;
      String? result;
      retryWithBackoff(
            () async {
              calls++;
              if (calls < 3) throw Exception('transient $calls');
              return 'ok';
            },
            label: 'test',
            maxAttempts: 5,
            baseDelay: const Duration(milliseconds: 100),
            maxDelay: const Duration(seconds: 1),
            random: Random(1),
          )
          .then((r) => result = r);

      async.elapse(const Duration(milliseconds: 500));

      expect(calls, 3);
      expect(result, 'ok');
    });
  });

  test('rethrows the last error once maxAttempts is exhausted', () {
    fakeAsync((async) {
      var calls = 0;
      Object? error;
      () async {
        try {
          await retryWithBackoff<void>(
            () async {
              calls++;
              throw Exception('fail $calls');
            },
            label: 'test',
            maxAttempts: 3,
            baseDelay: const Duration(milliseconds: 10),
            maxDelay: const Duration(milliseconds: 50),
          );
        } catch (e) {
          error = e;
        }
      }();

      async.elapse(const Duration(seconds: 1));

      expect(calls, 3);
      expect(error, isA<Exception>());
      expect(error.toString(), contains('fail 3'));
    });
  });

  test('retryIf returning false stops immediately, no delay/retry', () {
    fakeAsync((async) {
      var calls = 0;
      Object? error;
      () async {
        try {
          await retryWithBackoff<void>(
            () async {
              calls++;
              throw StateError('permanent');
            },
            label: 'test',
            maxAttempts: 5,
            retryIf: (e) => e is! StateError,
          );
        } catch (e) {
          error = e;
        }
      }();

      async.flushMicrotasks();

      expect(calls, 1);
      expect(error, isA<StateError>());
    });
  });
}
