import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/calls/matrixrtc/incoming_call_provider.dart';

void main() {
  group('RingRateLimiter', () {
    final start = DateTime(2026, 9, 4, 12);

    void flood(RingRateLimiter limiter, String senderId) {
      for (var i = 0; i < limiter.burst; i++) {
        limiter.allow(senderId, now: start);
      }
    }

    test('allows a normal burst — hanging up and calling back', () {
      final limiter = RingRateLimiter();

      for (final seconds in [0, 2, 4]) {
        expect(
          limiter.allow(
            '@bob:example.org',
            now: start.add(Duration(seconds: seconds)),
          ),
          isTrue,
          reason: 'ring at ${seconds}s',
        );
      }
    });

    test('drops a flood past the burst allowance', () {
      final limiter = RingRateLimiter();
      for (var i = 0; i < limiter.burst; i++) {
        expect(limiter.allow('@mallory:example.org', now: start), isTrue);
      }
      expect(limiter.allow('@mallory:example.org', now: start), isFalse);
      expect(
        limiter.allow(
          '@mallory:example.org',
          now: start.add(const Duration(seconds: 30)),
        ),
        isFalse,
      );
    });

    test('lets the budget recover once the window passes', () {
      final limiter = RingRateLimiter();
      flood(limiter, '@mallory:example.org');
      expect(
        limiter.allow(
          '@mallory:example.org',
          now: start.add(const Duration(minutes: 1, seconds: 1)),
        ),
        isTrue,
      );
    });

    test('budgets each sender separately', () {
      final limiter = RingRateLimiter();
      flood(limiter, '@mallory:example.org');
      expect(limiter.allow('@alice:example.org', now: start), isTrue);
    });

    test('forgets the oldest sender once it tracks too many, so memory stays '
        'bounded', () {
      final limiter = RingRateLimiter();
      flood(limiter, '@mallory:example.org');
      for (var i = 0; i < 500; i++) {
        limiter.allow('@user$i:example.org', now: start);
      }
      expect(limiter.allow('@mallory:example.org', now: start), isTrue);
    });
  });
}
