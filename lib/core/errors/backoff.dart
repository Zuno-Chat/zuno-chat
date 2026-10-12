import 'dart:math' as math;

Duration backoffDelay(
  int attempt, {
  required Duration baseDelay,
  required Duration maxDelay,
  math.Random? random,
}) {
  assert(attempt >= 1, 'attempt is 1-based');
  final ceilingMicros = math.min(
    baseDelay.inMicroseconds * math.pow(2.0, math.min(attempt - 1, 62)),
    maxDelay.inMicroseconds.toDouble(),
  );
  final draw = (random ?? math.Random()).nextDouble();
  return Duration(microseconds: (ceilingMicros * draw).round());
}
