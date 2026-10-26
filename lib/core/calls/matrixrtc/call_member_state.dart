import 'package:clock/clock.dart';
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

  bool get isExpired => clock.now().millisecondsSinceEpoch > expiresAtMs;

  static RtcMembership? tryParse(Object? json) {
    if (json case {
      'call_id': final String callId,
      'device_id': final String deviceId,
      'kind': final String kind,
      'expires_ts': final int expiresAtMs,
    }) {
      final createdAtMs = json['created_ts'] ?? 0;
      final fociActive = json['foci_active'] ?? const <String, Object?>{};
      if (createdAtMs is! int || fociActive is! Map) return null;
      return RtcMembership(
        callId: callId,
        deviceId: deviceId,
        kind: kind,
        expiresAtMs: expiresAtMs,
        createdAtMs: createdAtMs,
        fociActive: fociActive.cast<String, Object?>(),
      );
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'call_id': callId,
    'device_id': deviceId,
    'kind': kind,
    'expires_ts': expiresAtMs,
    'created_ts': createdAtMs,
    'foci_active': fociActive,
  };
}

typedef CallJoin = ({String userId, String? eventId, RtcMembership membership});

Iterable<CallJoin> callJoins(Room room, String callId) sync* {
  final states = room.states[callMemberEventType] ?? const {};
  for (final MapEntry(key: userId, value: state) in states.entries) {
    final eventId = state is MatrixEvent ? state.eventId : null;
    for (final membership in parseRtcMemberships(state.content)) {
      if (membership.callId == callId) {
        yield (userId: userId, eventId: eventId, membership: membership);
      }
    }
  }
}

String? callMembershipEventId(Room room, String callId, {String? excluding}) =>
    callJoins(room, callId)
        .where((join) => join.userId != excluding && join.eventId != null)
        .firstOrNull
        ?.eventId;

List<RtcMembership> parseRtcMemberships(
  Map<String, Object?>? content, {
  bool includeExpired = false,
}) {
  final raw = content?['memberships'];
  if (raw is! List) return [];
  return [
    for (final entry in raw)
      if (RtcMembership.tryParse(entry) case final membership?)
        if (includeExpired || !membership.isExpired) membership,
  ];
}

bool answeredOnAnotherDevice(Room room, String callId) {
  final client = room.client;
  return callJoins(room, callId).any(
    (join) =>
        join.userId == client.userID &&
        join.membership.deviceId != client.deviceID,
  );
}
