import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/background_long_poll.dart';

import '../../helpers/fake_matrix.dart';

class _PollingClient extends Client {
  _PollingClient() : super('test', database: FakeDatabaseApi());

  final timeouts = <Duration?>[];
  final answers = <Completer<void>>[];
  bool? background;

  @override
  bool isLogged() => true;

  @override
  set backgroundSync(bool enabled) => background = enabled;

  @override
  Future<void> oneShotSync({Duration? timeout}) {
    timeouts.add(timeout);
    final answer = Completer<void>();
    answers.add(answer);
    return answer.future;
  }
}

void main() {
  group('nextPollTimeout', () {
    test('a long poll that worked stays long', () {
      expect(
        nextPollTimeout(
          longPollTimeout,
          failed: false,
          waited: const Duration(seconds: 90),
        ),
        longPollTimeout,
      );
    });

    test('a long poll cut after half a minute falls back to short', () {
      expect(
        nextPollTimeout(
          longPollTimeout,
          failed: true,
          waited: const Duration(seconds: 60),
        ),
        shortPollTimeout,
      );
    });

    test('a quick failure is the network, not the length', () {
      expect(
        nextPollTimeout(
          longPollTimeout,
          failed: true,
          waited: const Duration(seconds: 2),
        ),
        longPollTimeout,
      );
    });
  });

  group('BackgroundLongPoll', () {
    test('takes over from the SDK loop with long polls', () {
      fakeAsync((async) {
        final client = _PollingClient();
        final poll = BackgroundLongPoll(client)..start();
        async.flushMicrotasks();

        expect(client.background, isFalse);
        expect(client.timeouts, [longPollTimeout]);

        client.answers.last.complete();
        async.elapse(Duration.zero);
        expect(client.timeouts, [longPollTimeout, longPollTimeout]);
        poll.stop();
      });
    });

    test('stops polling once stopped', () {
      fakeAsync((async) {
        final client = _PollingClient();
        final poll = BackgroundLongPoll(client)..start();
        async.flushMicrotasks();

        poll.stop();
        client.answers.last.complete();
        async.elapse(Duration.zero);

        expect(client.timeouts, hasLength(1));
        expect(poll.running, isFalse);
      });
    });

    test('falls back to short polls after a long one is cut', () {
      fakeAsync((async) {
        final client = _PollingClient();
        var now = DateTime.utc(2026, 10, 8, 12);
        final poll = BackgroundLongPoll(client, now: () => now)..start();
        async.flushMicrotasks();

        now = now.add(const Duration(seconds: 60));
        client.onSyncStatus.add(
          SyncStatusUpdate(
            SyncStatus.error,
            error: SdkError(exception: Exception('cut')),
          ),
        );
        async.flushMicrotasks();
        client.answers.last.complete();
        async.elapse(Duration.zero);

        expect(client.timeouts.last, shortPollTimeout);
        poll.stop();
      });
    });

    test('starting twice runs one loop', () {
      fakeAsync((async) {
        final client = _PollingClient();
        final poll = BackgroundLongPoll(client)
          ..start()
          ..start();
        async.flushMicrotasks();

        expect(client.timeouts, hasLength(1));
        poll.stop();
      });
    });
  });
}
