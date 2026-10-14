import 'package:flutter/foundation.dart' show immutable;

import '../l10n/l10n.dart';
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

List<RecentPush> recentPushesFromDeliveries(
  AppLocalizations l10n,
  List<PushDeliveryRecord> records,
) => [
  for (final record in records)
    RecentPush(
      at: record.receivedAt,
      summary: pushDeliverySummary(l10n, record),
      late: record.late,
    ),
];

List<RecentPush> recentPushesFromLogs(
  AppLocalizations l10n, {
  required List<String> extension,
  required List<String> app,
  List<LedgerCall> ledger = const [],
}) => [
  for (final line in extension) ?_push(l10n, line, _extensionOutcome),
  for (final line in app) ?_push(l10n, line, _ringOutcome),
  for (final call in ledger)
    if (call.source == 'push')
      RecentPush(at: call.at, summary: _callState(l10n, call.state)),
]..sort((a, b) => b.at.compareTo(a.at));

String? _extensionOutcome(AppLocalizations l10n, String event) {
  if (!event.startsWith('nse_') || event == 'nse_catchup') return null;
  return _messageOutcome(l10n, event.substring(4));
}

String? _ringOutcome(AppLocalizations l10n, String event) =>
    event == 'metrickit' ? null : _callOutcome(l10n, event);

RecentPush? _push(
  AppLocalizations l10n,
  String line,
  String? Function(AppLocalizations l10n, String event) outcome,
) {
  final parts = line.split(' ');
  if (parts.length < 2) return null;
  final at = DateTime.tryParse(parts[0]);
  final summary = outcome(l10n, parts[1]);
  if (at == null || summary == null) return null;
  final lag = _lag(parts.skip(2));
  return RecentPush(
    at: at.toLocal(),
    summary: lag == null
        ? summary
        : l10n.pushOutcomeArrivedAfter(summary, formatDeliveryDelay(l10n, lag)),
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

String _messageOutcome(AppLocalizations l10n, String code) => switch (code) {
  'shown' => l10n.pushOutcomeShown,
  'quiet' => l10n.pushOutcomeQuiet,
  'duplicate' => l10n.pushOutcomeAlreadyShown,
  'hidden' => l10n.pushOutcomeNothingNew,
  'read' => l10n.pushOutcomeReadElsewhere,
  'gone' => l10n.pushOutcomeGone,
  'rate_limited' => l10n.pushOutcomeRateLimited,
  'auth' || 'no_meta' => l10n.pushOutcomeUntilOpened,
  'route' => l10n.pushOutcomeNotFetched,
  'net' => l10n.pushOutcomeNoConnection,
  'utd' => l10n.pushOutcomeUndecryptable,
  'mismatch' => l10n.pushOutcomeSecurityCheck,
  'bfu' => l10n.pushOutcomeBeforeUnlock,
  'test' => l10n.pushOutcomeTest,
  'nothing' => l10n.pushOutcomeNoDetails,
  'fallback_ring' => l10n.pushOutcomeFallbackRing,
  'call_handled' => l10n.pushOutcomeCallHandled,
  'safe_mode' => l10n.pushOutcomeSafeMode,
  'malformed' => l10n.pushOutcomeMalformed,
  _ => l10n.pushOutcomeHandled,
};

String _callOutcome(AppLocalizations l10n, String code) => switch (code) {
  'ring' => l10n.pushOutcomeCallRang,
  'duplicate' => l10n.pushOutcomeCallAlreadyRinging,
  'stale' || 'bfu_stale' => l10n.pushOutcomeCallEndedFirst,
  'resolved' => l10n.pushOutcomeCallResolved,
  'busy_ringing' => l10n.pushOutcomeBusyRinging,
  'busy_active' ||
  'version_unknown_busy' ||
  'kid_unknown_busy' ||
  'bfu_busy' => l10n.pushOutcomeBusyActive,
  'canary' => l10n.pushOutcomeCanary,
  'own_call' => l10n.pushOutcomeOwnCall,
  'forged' => l10n.pushOutcomeCallForged,
  'signed_out' || 'no_session' => l10n.pushOutcomeCallSignedOut,
  'version_unknown' || 'kid_unknown' => l10n.pushOutcomeCallRangNoName,
  'version_unknown_limit' ||
  'kid_unknown_limit' => l10n.pushOutcomeCallKeyOutOfDate,
  'bfu_ring' => l10n.pushOutcomeCallRangNoNameBeforeUnlock,
  'bfu_unreadable' || 'bfu_skipped' => l10n.pushOutcomeCallNotShownBeforeUnlock,
  _ => l10n.pushOutcomeHandled,
};

String _callState(AppLocalizations l10n, String state) => switch (state) {
  'ringing' => l10n.pushCallRinging,
  'answered' => l10n.pushCallAnswered,
  'ended' => l10n.pushCallEnded,
  'declined' => l10n.pushCallDeclined,
  'missed' => l10n.pushCallMissed,
  _ => l10n.pushOutcomeHandled,
};
