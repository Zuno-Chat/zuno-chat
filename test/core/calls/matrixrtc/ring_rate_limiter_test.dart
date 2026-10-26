import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/calls/matrixrtc/incoming_call_provider.dart';

void main() {
  group('RingRateLimiter', () {
    final start = DateTime(2026, 9, 4, 12);

    bool allowAt(RingRateLimiter limiter, String senderId, DateTime at) =>
        withClock(Clock.fixed(at), () => limiter.allow(senderId));

    void flood(RingRateLimiter limiter, String senderId) {
      for (var i = 0; i < limiter.burst; i++) {
        allowAt(limiter, senderId, start);
      }
    }

    test('allows a normal burst — hanging up and calling back', () {
      final limiter = RingRateLimiter();

      for (final seconds in [0, 2, 4]) {
        expect(
          allowAt(
            limiter,
            '@bob:example.org',
            start.add(Duration(seconds: seconds)),
          ),
          isTrue,
          reason: 'ring at ${seconds}s',
        );
      }
    });

    test('drops a flood past the burst allowance', () {
      final limiter = RingRateLimiter();
      for (var i = 0; i < limiter.burst; i++) {
        expect(allowAt(limiter, '@mallory:example.org', start), isTrue);
      }
      expect(allowAt(limiter, '@mallory:example.org', start), isFalse);
      expect(
        allowAt(
          limiter,
          '@mallory:example.org',
          start.add(const Duration(seconds: 30)),
        ),
        isFalse,
      );
    });

    test('lets the budget recover once the window passes', () {
      final limiter = RingRateLimiter();
      flood(limiter, '@mallory:example.org');
      expect(
        allowAt(
          limiter,
          '@mallory:example.org',
          start.add(const Duration(minutes: 1, seconds: 1)),
        ),
        isTrue,
      );
    });

    test('budgets each sender separately', () {
      final limiter = RingRateLimiter();
      flood(limiter, '@mallory:example.org');
      expect(allowAt(limiter, '@alice:example.org', start), isTrue);
    });

    test('forgets the oldest sender once it tracks too many, so memory stays '
        'bounded', () {
      final limiter = RingRateLimiter();
      flood(limiter, '@mallory:example.org');
      for (var i = 0; i < 500; i++) {
        allowAt(limiter, '@user$i:example.org', start);
      }
      expect(allowAt(limiter, '@mallory:example.org', start), isTrue);
    });
  });
}
