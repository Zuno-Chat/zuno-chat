import '../../../core/format/date_labels.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/location/live_location_sharing.dart';
import '../../../core/location/live_location_viewing.dart';

String liveShareStatusText(
  LiveShareView share,
  DateTime now,
  DateLabels labels,
) {
  final l10n = labels.l10n;
  final until = labels.clock(share.endsAt);
  if (share.fromThisDevice) return l10n.locationUntil(until);
  final position = share.position;
  final refreshing = share.refreshingAt(now);
  switch (share.statusAt(now)) {
    case LiveShareStatus.waiting:
      return refreshing
          ? l10n.locationStatusUpdatingWaiting(until)
          : l10n.locationStatusWaiting(until);
    case LiveShareStatus.live:
      final age = labels.age(position!.at, now, inSentence: true);
      return refreshing
          ? l10n.locationStatusUpdatingLive(until, age)
          : l10n.locationStatusLive(until, age);
    case LiveShareStatus.notUpdating:
      final since = labels.clock(position!.at);
      return refreshing
          ? l10n.locationStatusUpdatingStale(until, since)
          : l10n.locationStatusStale(until, since);
  }
}

String liveSharersText(
  AppLocalizations l10n,
  List<String> others, {
  required bool includesYou,
}) {
  if (others.isEmpty) return l10n.locationYouSharing;
  if (includesYou) {
    return others.length == 1
        ? l10n.locationSharersYouAndOne(others.first)
        : l10n.locationSharersYouAndMany(others.length);
  }
  return switch (others.length) {
    1 => l10n.locationSharersOne(others.first),
    2 => l10n.locationSharersTwo(others.first, others[1]),
    _ => l10n.locationSharersMany(others.first, others.length - 1),
  };
}

String liveShareStartFailureText(
  AppLocalizations l10n,
  LiveShareStartFailure reason,
) => switch (reason) {
  LiveShareStartFailure.notAllowed => l10n.locationStartNotAllowed,
  LiveShareStartFailure.alreadySharing => l10n.locationAlreadySharing,
  LiveShareStartFailure.captureUnavailable =>
    l10n.locationStartCaptureUnavailable,
  LiveShareStartFailure.failed => l10n.locationStartFailed,
};
