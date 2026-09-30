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
