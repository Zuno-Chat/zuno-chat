import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/async/elapsed.dart';

void main() {
  test('the app measures spans with the device stopwatch, which a wall-clock '
      'change cannot move', () {
    final watch = startStopwatch();

    expect(watch.runtimeType, Stopwatch);
    expect(watch.isRunning, isTrue);
  });

  test('fake time drives it in tests', () {
    fakeAsync((async) {
      final watch = startStopwatch();

      async.elapse(const Duration(seconds: 3));

      expect(watch.elapsed, const Duration(seconds: 3));
    });
  });

  test('a test clock drives it too', () {
    var now = DateTime(2026, 10, 26);
    final watch = withClock(Clock(() => now), startStopwatch);

    now = now.add(const Duration(minutes: 2));

    expect(watch.elapsed, const Duration(minutes: 2));
  });
}
