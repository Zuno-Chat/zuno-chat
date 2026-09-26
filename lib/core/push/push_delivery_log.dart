import 'package:shared_preferences/shared_preferences.dart';

const pushDeliveryLogKey = 'push.recent_deliveries';

class PushDeliveryRecord {
  final DateTime receivedAt;
  final DateTime? sentAt;
  final String? originalPriority;
  final String? deliveredPriority;
  final bool deviceIdle;
  final int? standbyBucket;

  const PushDeliveryRecord({
    required this.receivedAt,
    required this.sentAt,
    required this.originalPriority,
    required this.deliveredPriority,
    required this.deviceIdle,
    required this.standbyBucket,
  });

  Duration? get delay {
    final sent = sentAt;
    if (sent == null) return null;
    final delay = receivedAt.difference(sent);
    return delay.isNegative ? Duration.zero : delay;
  }

  bool get downgraded =>
      originalPriority == 'high' && deliveredPriority == 'normal';
}

List<PushDeliveryRecord> parsePushDeliveryLog(String? text) => [
  for (final line in (text ?? '').split('\n')) ?_parseLine(line),
];

PushDeliveryRecord? _parseLine(String line) {
  final columns = line.split('\t');
  if (columns.length != 6) return null;
  final received = int.tryParse(columns[0]);
  if (received == null) return null;
  final sent = int.tryParse(columns[1]);
  return PushDeliveryRecord(
    receivedAt: DateTime.fromMillisecondsSinceEpoch(received),
    sentAt: sent == null ? null : DateTime.fromMillisecondsSinceEpoch(sent),
    originalPriority: columns[2].isEmpty ? null : columns[2],
    deliveredPriority: columns[3].isEmpty ? null : columns[3],
    deviceIdle: columns[4] == '1',
    standbyBucket: int.tryParse(columns[5]),
  );
}

Future<List<PushDeliveryRecord>> readPushDeliveryLog(
  SharedPreferences prefs,
) async {
  await prefs.reload();
  return parsePushDeliveryLog(prefs.getString(pushDeliveryLogKey));
}

String pushDeliverySummary(PushDeliveryRecord record) {
  final delay = record.delay;
  final bucket = _restrictedBucketLabel(record.standbyBucket);
  return [
    delay == null ? 'Arrived' : 'Arrived after ${formatDeliveryDelay(delay)}',
    if (record.downgraded)
      'lowered to normal priority'
    else if (record.deliveredPriority case final priority?)
      '$priority priority',
    if (record.deviceIdle) 'device asleep',
    if (bucket != null) 'standby bucket $bucket',
  ].join(', ');
}

String formatDeliveryDelay(Duration delay) {
  if (delay < const Duration(seconds: 1)) {
    return '${(delay.inMilliseconds / 1000).toStringAsFixed(1)} s';
  }
  if (delay < const Duration(minutes: 1)) return '${delay.inSeconds} s';
  if (delay < const Duration(hours: 1)) return '${delay.inMinutes} min';
  return '${delay.inHours} h';
}

String? _restrictedBucketLabel(int? bucket) => switch (bucket) {
  40 => 'rare',
  45 => 'restricted',
  50 => 'never',
  _ => null,
};
