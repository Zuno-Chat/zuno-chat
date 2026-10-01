import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/push/push_delivery_log.dart';

void main() {
  group('parsePushDeliveryLog', () {
    test('reads every column of a line', () {
      final records = parsePushDeliveryLog('2000\t1500\thigh\tnormal\t1\t40');

      final record = records.single;
      expect(record.receivedAt, DateTime.fromMillisecondsSinceEpoch(2000));
      expect(record.sentAt, DateTime.fromMillisecondsSinceEpoch(1500));
      expect(record.originalPriority, 'high');
      expect(record.deliveredPriority, 'normal');
      expect(record.deviceIdle, isTrue);
      expect(record.standbyBucket, 40);
    });

    test('keeps empty columns as unknown', () {
      final record = parsePushDeliveryLog('2000\t\t\t\t0\t').single;

      expect(record.sentAt, isNull);
      expect(record.originalPriority, isNull);
      expect(record.deliveredPriority, isNull);
      expect(record.deviceIdle, isFalse);
      expect(record.standbyBucket, isNull);
    });

    test('skips malformed lines and keeps the good ones in order', () {
      final records = parsePushDeliveryLog(
        '3000\t\thigh\thigh\t0\t10\nnot a line\nlater\t1\t2\n1000\t\t\t\t0\t',
      );

      expect(records.map((r) => r.receivedAt.millisecondsSinceEpoch), [
        3000,
        1000,
      ]);
    });

    test('reads lines that carry the newer timing columns', () {
      final record = parsePushDeliveryLog(
        '2000\t1500\thigh\tnormal\t1\t40\t12\t1\t40\tdart\t2340',
      ).single;

      expect(record.receivedAt.millisecondsSinceEpoch, 2000);
      expect(record.standbyBucket, 40);
    });

    test('an empty log has no records', () {
      expect(parsePushDeliveryLog(null), isEmpty);
      expect(parsePushDeliveryLog(''), isEmpty);
    });
  });

  test('reads the log the native side writes', () async {
    SharedPreferences.setMockInitialValues({
      pushDeliveryLogKey: '2000\t1500\thigh\thigh\t0\t10',
    });

    final records = await readPushDeliveryLog(
      await SharedPreferences.getInstance(),
    );

    expect(records.single.deliveredPriority, 'high');
  });

  group('a record', () {
    test('is downgraded only when high priority arrived as normal', () {
      expect(_record(original: 'high', delivered: 'normal').downgraded, isTrue);
      expect(_record(original: 'high', delivered: 'high').downgraded, isFalse);
      expect(
        _record(original: 'normal', delivered: 'normal').downgraded,
        isFalse,
      );
      expect(_record().downgraded, isFalse);
    });

    test('measures the delay from send to arrival, never negative', () {
      expect(_record(delayMs: 400).delay, const Duration(milliseconds: 400));
      expect(_record(delayMs: -900).delay, Duration.zero);
      expect(_record().delay, isNull);
    });
  });

  group('pushDeliverySummary', () {
    test('a prompt high priority push', () {
      expect(
        pushDeliverySummary(
          _record(delayMs: 400, original: 'high', delivered: 'high'),
        ),
        'Arrived after 0.4 s, high priority',
      );
    });

    test('a push held while the device slept after being downgraded', () {
      expect(
        pushDeliverySummary(
          _record(
            delayMs: 12 * 60 * 1000,
            original: 'high',
            delivered: 'normal',
            idle: true,
            bucket: 40,
          ),
        ),
        'Arrived after 12 min, lowered to normal priority, device asleep, '
        'standby bucket rare',
      );
    });

    test('a push with no send time or priority', () {
      expect(pushDeliverySummary(_record()), 'Arrived');
    });
  });

  test('formatDeliveryDelay picks a readable unit', () {
    expect(formatDeliveryDelay(const Duration(milliseconds: 80)), '0.1 s');
    expect(formatDeliveryDelay(const Duration(seconds: 42)), '42 s');
    expect(formatDeliveryDelay(const Duration(minutes: 5)), '5 min');
    expect(formatDeliveryDelay(const Duration(hours: 3)), '3 h');
  });
}

PushDeliveryRecord _record({
  int? delayMs,
  String? original,
  String? delivered,
  bool idle = false,
  int? bucket,
}) {
  final received = DateTime.fromMillisecondsSinceEpoch(10000000);
  return PushDeliveryRecord(
    receivedAt: received,
    sentAt: delayMs == null
        ? null
        : received.subtract(Duration(milliseconds: delayMs)),
    originalPriority: original,
    deliveredPriority: delivered,
    deviceIdle: idle,
    standbyBucket: bucket,
  );
}
