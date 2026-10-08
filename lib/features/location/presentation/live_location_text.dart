import '../../../core/location/live_location_sharing.dart';
import '../../../core/location/live_location_viewing.dart';

String liveShareStatusText(
  LiveShareView share,
  DateTime now,
  String Function(DateTime time) clock,
) {
  final until = 'Until ${clock(share.endsAt)}';
  if (share.fromThisDevice) return until;
  final position = share.position;
  final status = share.statusAt(now);
  final freshness = switch (status) {
    LiveShareStatus.waiting => 'waiting for location',
    LiveShareStatus.live => 'updated ${_ago(now.difference(position!.at))}',
    LiveShareStatus.notUpdating => 'not updated since ${clock(position!.at)}',
  };
  if (!share.refreshingAt(now)) return '$until · $freshness';
  return status == LiveShareStatus.live
      ? '$until · updating, last $freshness'
      : '$until · updating, $freshness';
}

String _ago(Duration elapsed) {
  if (elapsed.inMinutes < 1) return 'just now';
  return '${elapsed.inMinutes} min ago';
}

String liveSharersText(List<String> others, {required bool includesYou}) {
  if (others.isEmpty) return 'You are sharing your live location';
  final count = others.length + (includesYou ? 1 : 0);
  final verb = count == 1 ? 'is' : 'are';
  final lead = includesYou ? 'You' : others.first;
  final rest = includesYou ? others.length : others.length - 1;
  final who = switch (rest) {
    0 => lead,
    1 => '$lead and ${includesYou ? others.first : others[1]}',
    _ => '$lead and $rest others',
  };
  return '$who $verb sharing live location';
}

String liveShareStartFailureText(LiveShareStartFailure reason) =>
    switch (reason) {
      LiveShareStartFailure.notAllowed =>
        'You cannot share live location here.',
      LiveShareStartFailure.alreadySharing =>
        'You are already sharing your live location here.',
      LiveShareStartFailure.captureUnavailable =>
        'Live location could not start. Check that location is on, then '
            'try again.',
      LiveShareStartFailure.failed => 'Live location did not start. Try again.',
    };
