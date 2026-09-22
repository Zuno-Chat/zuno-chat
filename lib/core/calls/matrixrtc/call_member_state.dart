import 'package:matrix/matrix.dart';

const callMemberEventType = 'm.call.member';

bool canPublishCallMemberState(Room room) =>
    room.canChangeStateEvent(callMemberEventType);

bool hasSomeoneToCall(Room room) {
  final joined = room.summary.mJoinedMemberCount;
  if (joined != null) return joined > 1;
  return room
      .getParticipants([Membership.join])
      .any((user) => user.id != room.client.userID);
}

class RtcMembership {
  final String callId;
  final String deviceId;
  final String kind;
  final int expiresAtMs;
  final int createdAtMs;
  final Map<String, Object?> fociActive;

  const RtcMembership({
    required this.callId,
    required this.deviceId,
    required this.kind,
    required this.expiresAtMs,
    this.createdAtMs = 0,
    required this.fociActive,
  });

  bool get isExpired => DateTime.now().millisecondsSinceEpoch > expiresAtMs;

  factory RtcMembership.fromJson(Map<String, Object?> json) => RtcMembership(
    callId: json['call_id'] as String,
    deviceId: json['device_id'] as String,
    kind: json['kind'] as String,
    expiresAtMs: json['expires_ts'] as int,
    createdAtMs: json['created_ts'] as int? ?? 0,
    fociActive:
        (json['foci_active'] as Map?)?.cast<String, Object?>() ?? const {},
  );

  Map<String, Object?> toJson() => {
    'call_id': callId,
    'device_id': deviceId,
    'kind': kind,
    'expires_ts': expiresAtMs,
    'created_ts': createdAtMs,
    'foci_active': fociActive,
  };
}

List<RtcMembership> parseRtcMemberships(Map<String, Object?>? content) {
  final raw = content?['memberships'];
  if (raw is! List) return [];
  return raw
      .whereType<Map>()
      .map((m) => RtcMembership.fromJson(m.cast<String, Object?>()))
      .where((m) => !m.isExpired)
      .toList();
}
