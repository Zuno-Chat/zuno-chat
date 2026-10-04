import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/push/push_delivery_log.dart';
import 'package:zuno/core/push/push_diagnostics_data.dart';
import 'package:zuno/core/push/recent_pushes.dart';

const _messageCodes = [
  'shown',
  'quiet',
  'duplicate',
  'hidden',
  'read',
  'gone',
  'rate_limited',
  'auth',
  'route',
  'net',
  'utd',
  'mismatch',
  'bfu',
  'no_meta',
  'test',
  'nothing',
  'fallback_ring',
  'call_handled',
  'safe_mode',
  'malformed',
];

const _ringCodes = [
  'ring',
  'duplicate',
  'stale',
  'resolved',
  'busy_ringing',
  'busy_active',
  'canary',
  'own_call',
  'forged',
  'signed_out',
  'no_session',
  'version_unknown',
  'kid_unknown',
  'version_unknown_limit',
  'kid_unknown_limit',
  'version_unknown_busy',
  'kid_unknown_busy',
  'bfu_ring',
  'bfu_unreadable',
  'bfu_stale',
  'bfu_skipped',
  'bfu_busy',
];

void main() {
  group('Apple logs', () {
    test('message and call lines read in plain words, newest first', () {
      final pushes = recentPushesFromLogs(
        extension: [
          '2026-10-03T21:00:00.000Z nse_shown t=abcd1234 ms=120 lag=1200 safe=0',
          '2026-10-03T21:02:00.000Z nse_utd t=abcd1234 ms=300 lag=90000 safe=0',
        ],
        app: ['2026-10-03T21:01:00.000Z ring ms=40 must=1 lag=800 t=abcd1234'],
      );

      expect(
        [for (final push in pushes) push.summary],
        [
          'Could not be decrypted, shown without the message. Arrived after 1 min',
          'Call rang. Arrived after 0.8 s',
          'Shown. Arrived after 1 s',
        ],
      );
      expect([for (final push in pushes) push.late], [true, false, false]);
      expect(pushes.last.at, DateTime.utc(2026, 10, 3, 21).toLocal());
    });

    test(
      'catch-up summaries, device reports and broken lines are left out',
      () {
        final pushes = recentPushesFromLogs(
          extension: [
            '2026-10-03T21:00:00.000Z nse_catchup posted=2 hidden=0',
            'not a log line',
            '',
            'yesterday nse_shown',
          ],
          app: ['2026-10-03T21:00:00.000Z metrickit summary=x'],
        );

        expect(pushes, isEmpty);
      },
    );

    test('an unknown outcome reads as Handled, and a missing or broken lag '
        'adds nothing', () {
      final pushes = recentPushesFromLogs(
        extension: ['2026-10-03T21:00:00.000Z nse_brand_new t=- ms=1 safe=0'],
        app: ['2026-10-03T21:01:00.000Z new_ring_rule ms=4 lag=soon'],
      );

      expect([for (final push in pushes) push.summary], ['Handled', 'Handled']);
      expect(pushes.any((push) => push.late), isFalse);
    });

    test('a clock running ahead never gives a negative delay', () {
      final push = recentPushesFromLogs(
        extension: [
          '2026-10-03T21:00:00.000Z nse_shown t=- ms=1 lag=-4000 safe=0',
        ],
        app: const [],
      ).single;

      expect(push.summary, 'Shown. Arrived after 0.0 s');
      expect(push.late, isFalse);
    });

    test('every extension outcome and ring decision has its own words', () {
      for (final code in _messageCodes) {
        final push = recentPushesFromLogs(
          extension: ['2026-10-03T21:00:00.000Z nse_$code'],
          app: const [],
        ).single;
        expect(push.summary, isNot('Handled'), reason: code);
      }
      for (final code in _ringCodes) {
        final push = recentPushesFromLogs(
          extension: const [],
          app: ['2026-10-03T21:00:00.000Z $code'],
        ).single;
        expect(push.summary, isNot('Handled'), reason: code);
      }
    });

    test('calls that rang from a push add their last state; calls from sync '
        'do not', () {
      final at = DateTime(2026, 10, 3, 21, 5);
      final pushes = recentPushesFromLogs(
        extension: const [],
        app: const [],
        ledger: [
          LedgerCall(state: 'missed', source: 'push', at: at),
          LedgerCall(state: 'answered', source: 'sync', at: at),
        ],
      );

      expect(pushes.single.summary, 'Missed call');
      expect(pushes.single.at, at);
    });
  });

  test('Android deliveries keep their summary and late flag', () {
    final received = DateTime(2026, 10, 3, 21);
    final pushes = recentPushesFromDeliveries([
      PushDeliveryRecord(
        receivedAt: received,
        sentAt: received.subtract(const Duration(minutes: 5)),
        originalPriority: 'high',
        deliveredPriority: 'high',
        deviceIdle: true,
        standbyBucket: null,
      ),
    ]);

    expect(
      pushes.single.summary,
      'Arrived after 5 min, high priority, device asleep',
    );
    expect(pushes.single.late, isTrue);
  });
}
