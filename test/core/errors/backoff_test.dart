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
  const baseDelay = Duration(milliseconds: 200);
  const maxDelay = Duration(seconds: 2);

  test('full jitter draws between zero and the exponential ceiling', () {
    expect(
      backoffDelay(
        1,
        baseDelay: baseDelay,
        maxDelay: maxDelay,
        random: const _FixedRandom(0),
      ),
      Duration.zero,
    );
    expect(
      backoffDelay(
        5,
        baseDelay: baseDelay,
        maxDelay: maxDelay,
        random: const _FixedRandom(0),
      ),
      Duration.zero,
    );
  });

  test('ceiling doubles each attempt when nextDouble() == 1', () {
    expect(
      backoffDelay(
        1,
        baseDelay: baseDelay,
        maxDelay: maxDelay,
        random: const _FixedRandom(1),
      ),
      const Duration(milliseconds: 200),
    );
    expect(
      backoffDelay(
        2,
        baseDelay: baseDelay,
        maxDelay: maxDelay,
        random: const _FixedRandom(1),
      ),
      const Duration(milliseconds: 400),
    );
    expect(
      backoffDelay(
        3,
        baseDelay: baseDelay,
        maxDelay: maxDelay,
        random: const _FixedRandom(1),
      ),
      const Duration(milliseconds: 800),
    );
  });

  test('ceiling is capped at maxDelay once the exponential exceeds it', () {
    expect(
      backoffDelay(
        5,
        baseDelay: baseDelay,
        maxDelay: maxDelay,
        random: const _FixedRandom(1),
      ),
      maxDelay,
    );
  });

  test('a mid-range draw scales linearly within the ceiling', () {
    expect(
      backoffDelay(
        1,
        baseDelay: baseDelay,
        maxDelay: maxDelay,
        random: const _FixedRandom(0.5),
      ),
      const Duration(milliseconds: 100),
    );
  });
}
