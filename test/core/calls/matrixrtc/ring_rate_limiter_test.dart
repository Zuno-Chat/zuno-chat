import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/calls/matrixrtc/incoming_call_provider.dart';

void main() {
  group('RingRateLimiter', () {
    final start = DateTime(2026, 9, 4, 12);

    test('allows a normal burst — hanging up and calling back', () {
      final limiter = RingRateLimiter();
      expect(limiter.allow('@bob:example.org', now: start), isTrue);
      expect(
        limiter.allow('@bob:example.org', now: start.add(const Duration(seconds: 2))),
        isTrue,
      );
      expect(
        limiter.allow('@bob:example.org', now: start.add(const Duration(seconds: 4))),
        isTrue,
      );
    });

    test('drops a flood past the burst allowance', () {
      final limiter = RingRateLimiter();
      for (var i = 0; i < limiter.burst; i++) {
        expect(limiter.allow('@mallory:example.org', now: start), isTrue);
      }
      expect(limiter.allow('@mallory:example.org', now: start), isFalse);
      expect(
        limiter.allow('@mallory:example.org',
            now: start.add(const Duration(seconds: 30))),
        isFalse,
      );
    });

    test('lets the budget recover once the window passes', () {
      final limiter = RingRateLimiter();
      for (var i = 0; i < limiter.burst; i++) {
        limiter.allow('@mallory:example.org', now: start);
      }
      expect(
        limiter.allow('@mallory:example.org',
            now: start.add(const Duration(minutes: 1, seconds: 1))),
        isTrue,
      );
    });

    test('budgets each sender separately', () {
      final limiter = RingRateLimiter();
      for (var i = 0; i < limiter.burst; i++) {
        limiter.allow('@mallory:example.org', now: start);
      }
      expect(limiter.allow('@alice:example.org', now: start), isTrue);
    });

    test('does not grow without bound across many senders', () {
      final limiter = RingRateLimiter();
      for (var i = 0; i < 500; i++) {
        limiter.allow('@user$i:example.org', now: start);
      }
      expect(limiter.allow('@newcomer:example.org', now: start), isTrue);
    });
  });
}
