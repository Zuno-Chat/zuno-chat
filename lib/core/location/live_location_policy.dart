import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'geo_uri.dart';
import 'live_location_protocol.dart';

enum LiveLocationMode { coarse, precise }

enum LiveAudience { everyone, watchers }

const liveWatchRenewInterval = Duration(seconds: 60);
const liveWatchLifetime = Duration(minutes: 2);
const liveStaleAfter = Duration(minutes: 15);

const _everyoneHeartbeat = Duration(minutes: 5);
const _heartbeatSlack = Duration(seconds: 30);
const _watchersHeartbeat = Duration(seconds: 30);
const _watchersMinGap = Duration(seconds: 5);
const _watchersMoveMeters = 10.0;
const _clockMovedBack = Duration(days: 365);
const _distance = Distance(roundResult: false, calculator: Haversine());

@immutable
class LiveSendRecord {
  final LivePosition position;
  final DateTime sentAt;

  const LiveSendRecord({required this.position, required this.sentAt});
}

LiveLocationMode liveCaptureModeFor({required bool watched}) =>
    watched ? LiveLocationMode.precise : LiveLocationMode.coarse;

LiveAudience? nextLiveAudience({
  required LivePosition latest,
  required LiveSendRecord? lastToEveryone,
  required LiveSendRecord? lastToWatchers,
  required bool hasWatchers,
  required DateTime now,
}) {
  if (lastToEveryone == null) return LiveAudience.everyone;
  if (latest != lastToEveryone.position &&
      _elapsed(now, lastToEveryone.sentAt) >=
          _everyoneHeartbeat - _heartbeatSlack) {
    return LiveAudience.everyone;
  }
  if (!hasWatchers) return null;
  final reference =
      lastToWatchers == null ||
          lastToEveryone.sentAt.isAfter(lastToWatchers.sentAt)
      ? lastToEveryone
      : lastToWatchers;
  if (latest == reference.position) return null;
  final sinceWatchers = _elapsed(now, reference.sentAt);
  if (sinceWatchers < _watchersMinGap) return null;
  if (sinceWatchers >= _watchersHeartbeat ||
      _moved(latest, reference.position, _watchersMoveMeters) ||
      _sharpened(latest.geo, reference.position.geo, _watchersMoveMeters)) {
    return LiveAudience.watchers;
  }
  return null;
}

Duration _elapsed(DateTime now, DateTime since) {
  final gap = now.difference(since);
  return gap.isNegative ? _clockMovedBack : gap;
}

bool _moved(LivePosition latest, LivePosition reference, double threshold) {
  final meters = _distance
      .distance(_point(latest.geo), _point(reference.geo))
      .toDouble();
  final noise =
      (latest.geo.uncertaintyMeters ?? 0) +
      (reference.geo.uncertaintyMeters ?? 0);
  return meters >= threshold && meters > noise;
}

LatLng _point(GeoUri geo) => LatLng(geo.latitude, geo.longitude);

bool _sharpened(GeoUri latest, GeoUri reference, double threshold) {
  final now = latest.uncertaintyMeters;
  final before = reference.uncertaintyMeters;
  return now != null &&
      before != null &&
      before > threshold &&
      now * 2 <= before;
}
