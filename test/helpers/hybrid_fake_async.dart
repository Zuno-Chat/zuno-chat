import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

extension HybridFakeAsync on FakeAsync {
  Future<void> settle() async {
    for (var round = 0; round < 20; round++) {
      await pumpEventQueue(times: 1);
      elapse(Duration.zero);
    }
  }

  Future<void> advance(
    Duration duration, {
    Duration step = const Duration(milliseconds: 100),
  }) async {
    var left = duration;
    while (left > Duration.zero) {
      await settle();
      final next = left < step ? left : step;
      elapse(next);
      left -= next;
    }
    await settle();
  }
}

const _drainRounds = 20;

extension FakeAsyncDrain on FakeAsync {
  T waitFor<T>(Future<T> future, {Duration elapsing = Duration.zero}) {
    late T value;
    Object? error;
    var done = false;
    future.then(
      (v) {
        value = v;
        done = true;
      },
      onError: (Object e) {
        error = e;
        done = true;
      },
    );
    if (elapsing > Duration.zero) elapse(elapsing);
    for (var i = 0; i < _drainRounds && !done; i++) {
      flushMicrotasks();
      elapse(Duration.zero);
    }
    if (error case final e?) throw e;
    expect(done, isTrue, reason: 'the future never completed');
    return value;
  }

  void flushAll() {
    for (var i = 0; i < _drainRounds; i++) {
      flushMicrotasks();
      elapse(Duration.zero);
    }
  }
}
