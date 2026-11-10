import 'package:matrix/matrix.dart';

import 'call_member_state.dart';
import 'call_moderation.dart';
import 'call_removed_event.dart';

Map<String, String> callRemovals(Room room, String callId) => {
  for (final MapEntry(key: stateKey, value: state)
      in (room.states[callRemovedEventType] ?? const {}).entries)
    if (removedUserOf(stateKey) case final userId?
        when state.content['call_id'] == callId &&
            callModerationGate(room, actorId: state.senderId)(userId))
      userId: state.senderId,
};

class CallRemovals {
  CallRemovals(this.callId);

  final String callId;
  final Map<String, String> _seen = {};

  void saw(String userId, {required String by}) => _seen[userId] = by;

  Map<String, String> current(Room room) {
    _seen.addAll(callRemovals(room, callId));
    return {
      for (final MapEntry(key: userId, value: moderator) in _seen.entries)
        if (callModerationGate(room, actorId: moderator)(userId))
          userId: moderator,
    };
  }
}

Iterable<CallJoin> currentCallJoins(
  Room room,
  String callId,
  Map<String, String> removals,
) => callJoins(room, callId).where(
  (join) =>
      !removals.containsKey(join.userId) && !_outOfRoom(room, join.userId),
);

bool _outOfRoom(Room room, String userId) => switch (room
    .getState(EventTypes.RoomMember, userId)
    ?.content['membership']) {
  null || 'join' => false,
  _ => true,
};
