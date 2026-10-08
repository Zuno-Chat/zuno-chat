import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import 'geo_uri.dart';

const liveLocationStateType = 'im.zuno.live_location';
const liveLocationMsgtype = 'im.zuno.live_location';
const liveLocationPositionType = 'im.zuno.live_location.position';
const liveLocationWatchType = 'im.zuno.live_location.watch';

const _longestShareWithSkew = Duration(hours: 2, minutes: 10);
const _maxIdLength = 255;
const _maxDateMilliseconds = 8640000000000000;

enum LiveLocationDuration {
  quarterHour(Duration(minutes: 15), '15 minutes'),
  hour(Duration(hours: 1), '1 hour'),
  twoHours(Duration(hours: 2), '2 hours');

  const LiveLocationDuration(this.duration, this.label);

  final Duration duration;
  final String label;
}

@immutable
class LiveShareState {
  final String shareId;
  final String deviceId;
  final DateTime endsAt;

  const LiveShareState({
    required this.shareId,
    required this.deviceId,
    required this.endsAt,
  });

  bool isOpenAt(DateTime now) => now.isBefore(endsAt);

  Map<String, Object?> toContent() => {
    'share_id': shareId,
    'device_id': deviceId,
    'ends_ts': endsAt.millisecondsSinceEpoch,
  };

  @override
  bool operator ==(Object other) =>
      other is LiveShareState &&
      other.shareId == shareId &&
      other.deviceId == deviceId &&
      other.endsAt == endsAt;

  @override
  int get hashCode => Object.hash(shareId, deviceId, endsAt);
}

LiveShareState? parseLiveShareState(
  Map<String, Object?>? content, {
  required DateTime publishedAt,
}) {
  if (content == null) return null;
  final shareId = _id(content['share_id']);
  final deviceId = _id(content['device_id']);
  final endsAt = _endWithin(content['ends_ts'], publishedAt);
  if (shareId == null || deviceId == null || endsAt == null) return null;
  return LiveShareState(shareId: shareId, deviceId: deviceId, endsAt: endsAt);
}

LiveShareState? liveShareStateOf(Room room, String userId) {
  final state = room.states[liveLocationStateType]?[userId];
  if (state is! MatrixEvent || state.senderId != userId) return null;
  return parseLiveShareState(state.content, publishedAt: state.originServerTs);
}

Map<String, Object?> liveLocationStartContent({
  required String shareId,
  required DateTime endsAt,
  required LiveLocationDuration duration,
}) => {
  'msgtype': liveLocationMsgtype,
  'body': 'Live location for ${duration.label}',
  'share_id': shareId,
  'ends_ts': endsAt.millisecondsSinceEpoch,
};

@immutable
class LiveLocationStart {
  final String shareId;
  final DateTime endsAt;

  const LiveLocationStart({required this.shareId, required this.endsAt});

  @override
  bool operator ==(Object other) =>
      other is LiveLocationStart &&
      other.shareId == shareId &&
      other.endsAt == endsAt;

  @override
  int get hashCode => Object.hash(shareId, endsAt);
}

LiveLocationStart? liveLocationStartOf(Event event) {
  if (event.type != EventTypes.Message) return null;
  if (event.messageType != liveLocationMsgtype) return null;
  final shareId = _id(event.content['share_id']);
  final endsAt = _endWithin(event.content['ends_ts'], event.originServerTs);
  if (shareId == null || endsAt == null) return null;
  return LiveLocationStart(shareId: shareId, endsAt: endsAt);
}

@immutable
class LivePosition {
  final GeoUri geo;
  final DateTime at;

  const LivePosition({required this.geo, required this.at});

  @override
  bool operator ==(Object other) =>
      other is LivePosition && other.geo == geo && other.at == at;

  @override
  int get hashCode => Object.hash(geo, at);
}

Map<String, Object?> livePositionContent({
  required String roomId,
  required String shareId,
  required LivePosition position,
}) => {
  'room_id': roomId,
  'share_id': shareId,
  'geo_uri': position.geo.toUriString(),
  'ts': position.at.millisecondsSinceEpoch,
};

({String roomId, String shareId, LivePosition position})? parseLivePosition(
  Map<String, Object?> content,
) {
  final roomId = _id(content['room_id']);
  final shareId = _id(content['share_id']);
  final geo = switch (content['geo_uri']) {
    final String uri => GeoUri.tryParse(uri),
    _ => null,
  };
  final at = liveTimestamp(content['ts']);
  if (roomId == null || shareId == null || geo == null || at == null) {
    return null;
  }
  return (
    roomId: roomId,
    shareId: shareId,
    position: LivePosition(geo: geo, at: at),
  );
}

Map<String, Object?> liveWatchContent({
  required String roomId,
  required String shareId,
  required bool active,
}) => {'room_id': roomId, 'share_id': shareId, 'active': active};

({String roomId, String shareId, bool active})? parseLiveWatch(
  Map<String, Object?> content,
) {
  final roomId = _id(content['room_id']);
  final shareId = _id(content['share_id']);
  final active = content['active'];
  if (roomId == null || shareId == null || active is! bool) return null;
  return (roomId: roomId, shareId: shareId, active: active);
}

String newLiveShareId([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = Uint8List.fromList([
    for (var i = 0; i < 16; i++) source.nextInt(256),
  ]);
  return base64Url.encode(bytes).replaceAll('=', '');
}

String? _id(Object? value) =>
    value is String && value.isNotEmpty && value.length <= _maxIdLength
    ? value
    : null;

DateTime? liveTimestamp(Object? value) {
  if (value is! int || value.abs() > _maxDateMilliseconds) return null;
  return DateTime.fromMillisecondsSinceEpoch(value);
}

DateTime? _endWithin(Object? value, DateTime publishedAt) {
  final end = liveTimestamp(value);
  if (end == null || end.isAfter(publishedAt.add(_longestShareWithSkew))) {
    return null;
  }
  return end;
}
