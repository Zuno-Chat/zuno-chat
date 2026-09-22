import 'dart:async' show FutureOr;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;

import 'backoff.dart';

Future<T> retryWithBackoff<T>(
  FutureOr<T> Function() request, {
  required String label,
  int maxAttempts = 3,
  Duration baseDelay = const Duration(milliseconds: 200),
  Duration maxDelay = const Duration(seconds: 2),
  bool Function(Object error)? retryIf,
  Duration? Function(Object error)? retryAfter,
  math.Random? random,
}) async {
  var attempt = 0;
  while (true) {
    attempt++;
    try {
      return await request();
    } catch (error) {
      final attemptsLeft = attempt < maxAttempts;
      final worthRetrying = retryIf?.call(error) ?? true;
      if (!attemptsLeft || !worthRetrying) rethrow;
      final requested = retryAfter?.call(error);
      final Duration delay;
      if (requested == null) {
        delay = backoffDelay(
          attempt,
          baseDelay: baseDelay,
          maxDelay: maxDelay,
          random: random,
        );
      } else {
        delay = requested < maxDelay ? requested : maxDelay;
      }
      debugPrint(
        'zuno/retry: $label failed (attempt $attempt/$maxAttempts), '
        'retrying in $delay: $error',
      );
      await Future.delayed(delay);
    }
  }
}
