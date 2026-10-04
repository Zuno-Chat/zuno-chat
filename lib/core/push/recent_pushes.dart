import 'package:flutter/foundation.dart' show immutable;

import 'push_delivery_log.dart';
import 'push_diagnostics_data.dart' show LedgerCall;

@immutable
class RecentPush {
  const RecentPush({
    required this.at,
    required this.summary,
    this.late = false,
  });

  final DateTime at;
  final String summary;
  final bool late;
}

const shownRecentPushes = 10;

List<RecentPush> recentPushesFromDeliveries(List<PushDeliveryRecord> records) =>
    [
      for (final record in records)
        RecentPush(
          at: record.receivedAt,
          summary: pushDeliverySummary(record),
          late: record.late,
        ),
    ];

List<RecentPush> recentPushesFromLogs({
  required List<String> extension,
  required List<String> app,
  List<LedgerCall> ledger = const [],
}) => [
  for (final line in extension) ?_push(line, _extensionOutcome),
  for (final line in app) ?_push(line, _ringOutcome),
  for (final call in ledger)
    if (call.source == 'push')
      RecentPush(at: call.at, summary: _callStates[call.state] ?? 'Handled'),
]..sort((a, b) => b.at.compareTo(a.at));

String? _extensionOutcome(String event) {
  if (!event.startsWith('nse_') || event == 'nse_catchup') return null;
  return _messageOutcomes[event.substring(4)] ?? 'Handled';
}

String? _ringOutcome(String event) =>
    event == 'metrickit' ? null : _ringOutcomes[event] ?? 'Handled';

RecentPush? _push(String line, String? Function(String event) outcome) {
  final parts = line.split(' ');
  if (parts.length < 2) return null;
  final at = DateTime.tryParse(parts[0]);
  final summary = outcome(parts[1]);
  if (at == null || summary == null) return null;
  final lag = _lag(parts.skip(2));
  return RecentPush(
    at: at.toLocal(),
    summary: lag == null
        ? summary
        : '$summary. Arrived after ${formatDeliveryDelay(lag)}',
    late: lag != null && lag > lateArrival,
  );
}

Duration? _lag(Iterable<String> fields) {
  for (final field in fields) {
    if (!field.startsWith('lag=')) continue;
    final milliseconds = int.tryParse(field.substring(4));
    if (milliseconds == null) return null;
    return Duration(milliseconds: milliseconds < 0 ? 0 : milliseconds);
  }
  return null;
}

const _messageOutcomes = {
  'shown': 'Shown',
  'quiet': 'Shown silently, it did not mention you',
  'duplicate': 'Already shown',
  'hidden': 'Nothing new to show',
  'read': 'Already read on another device',
  'gone': 'Shown without the message, it is no longer available',
  'rate_limited': 'Shown without the message, too many arrived at once',
  'auth': 'Shown without the message until Zuno is opened',
  'route': 'Shown without the message, it could not be fetched',
  'net': 'Shown without the message, there was no connection',
  'utd': 'Could not be decrypted, shown without the message',
  'mismatch': 'Shown without the message, it failed a security check',
  'bfu': 'Shown without the message, it arrived before the first unlock',
  'no_meta': 'Shown without the message until Zuno is opened',
  'test': 'Test notification',
  'nothing': 'Shown without details, as set in Notification content',
  'fallback_ring': 'Ring shown by Zuno, the system call screen did not ring',
  'call_handled': 'No notification needed for this call',
  'safe_mode': 'Shown without the message after a recent crash',
  'malformed': 'Shown as sent, the push was incomplete',
};

const _ringOutcomes = {
  'ring': 'Call rang',
  'duplicate': 'Call already ringing',
  'stale': 'Call ended before it arrived',
  'resolved': 'Call already answered or ended',
  'busy_ringing': 'Arrived while another call was ringing',
  'busy_active': 'Arrived during another call',
  'canary': 'Call check, nothing shown',
  'own_call': 'Your own call, nothing shown',
  'forged': 'Call refused, it failed a security check',
  'signed_out': 'Call arrived while signed out',
  'no_session': 'Call arrived while signed out',
  'version_unknown': "Call rang without the caller's name",
  'kid_unknown': "Call rang without the caller's name",
  'version_unknown_limit': 'Call not shown, the call key is out of date',
  'kid_unknown_limit': 'Call not shown, the call key is out of date',
  'version_unknown_busy': 'Arrived during another call',
  'kid_unknown_busy': 'Arrived during another call',
  'bfu_ring': "Call rang without the caller's name, before the first unlock",
  'bfu_unreadable': 'Call not shown, it arrived before the first unlock',
  'bfu_stale': 'Call ended before it arrived',
  'bfu_skipped': 'Call not shown, it arrived before the first unlock',
  'bfu_busy': 'Arrived during another call',
};

const _callStates = {
  'ringing': 'Call ringing',
  'answered': 'Call answered',
  'ended': 'Call ended',
  'declined': 'Call declined',
  'missed': 'Missed call',
};
