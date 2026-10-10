import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/errors/backoff.dart';

class _FixedRandom implements Random {
  final double value;
  const _FixedRandom(this.value);

  @override
  double nextDouble() => value;

  @override
  int nextInt(int max) => (value * max).floor();

  @override
  bool nextBool() => value >= 0.5;
}

void main() {
  const maxDelay = Duration(seconds: 2);

  Duration delay(int attempt, double draw) => backoffDelay(
    attempt,
    baseDelay: const Duration(milliseconds: 200),
    maxDelay: maxDelay,
    random: _FixedRandom(draw),
  );

  test('full jitter draws between zero and the exponential ceiling', () {
    expect(delay(1, 0), Duration.zero);
    expect(delay(5, 0), Duration.zero);
  });

  test('ceiling doubles each attempt when nextDouble() == 1', () {
    expect(delay(1, 1), const Duration(milliseconds: 200));
    expect(delay(2, 1), const Duration(milliseconds: 400));
    expect(delay(3, 1), const Duration(milliseconds: 800));
  });

  test('ceiling is capped at maxDelay once the exponential exceeds it', () {
    expect(delay(5, 1), maxDelay);
  });

  test('a mid-range draw scales linearly within the ceiling', () {
    expect(delay(1, 0.5), const Duration(milliseconds: 100));
  });
}
