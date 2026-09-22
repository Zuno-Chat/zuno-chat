import 'package:matrix/matrix.dart';

import 'call_member_state.dart';

class ActiveRoomCall {
  final String callId;
  final String kind;
  final List<String> participantUserIds;

  const ActiveRoomCall({
    required this.callId,
    required this.kind,
    required this.participantUserIds,
  });
}

ActiveRoomCall? findActiveRoomCall(Room room, {required String excludeUserId}) {
  final states = room.states[callMemberEventType] ?? const {};
  final participantsByCallId = <String, Set<String>>{};
  final kindByCallId = <String, String>{};

  for (final entry in states.entries) {
    if (entry.key == excludeUserId) continue;
    final memberships = parseRtcMemberships(entry.value.content);
    if (memberships.isEmpty) continue;
    final membership = memberships.first;
    participantsByCallId
        .putIfAbsent(membership.callId, () => {})
        .add(entry.key);
    kindByCallId[membership.callId] = membership.kind;
  }
  if (participantsByCallId.isEmpty) return null;

  final bestCallId = participantsByCallId.entries.reduce((a, b) {
    if (a.value.length != b.value.length) {
      return a.value.length > b.value.length ? a : b;
    }
    return a.key.compareTo(b.key) <= 0 ? a : b;
  }).key;

  return ActiveRoomCall(
    callId: bestCallId,
    kind: kindByCallId[bestCallId]!,
    participantUserIds: participantsByCallId[bestCallId]!.toList(),
  );
}

const maxCallParticipants = 6;

List<String> _participantsInJoinOrder(Room room, String callId) {
  final joinedAt = <String, int>{};
  final states = room.states[callMemberEventType] ?? const {};
  for (final entry in states.entries) {
    for (final membership in parseRtcMemberships(entry.value.content)) {
      if (membership.callId != callId) continue;
      final earliest = joinedAt[entry.key];
      if (earliest == null || membership.createdAtMs < earliest) {
        joinedAt[entry.key] = membership.createdAtMs;
      }
    }
  }
  return joinedAt.keys.toList()..sort((a, b) {
    final byTime = joinedAt[a]!.compareTo(joinedAt[b]!);
    return byTime != 0 ? byTime : a.compareTo(b);
  });
}

bool isCallFull(Room room, String callId, {required String excludeUserId}) {
  final others = _participantsInJoinOrder(
    room,
    callId,
  ).where((id) => id != excludeUserId);
  return others.length >= maxCallParticipants;
}

bool isOverCallCapacity(Room room, String callId, String userId) =>
    _participantsInJoinOrder(room, callId).indexOf(userId) >=
    maxCallParticipants;
