import 'package:matrix/matrix.dart';

import 'call_member_state.dart';
import 'call_summary_message.dart';

Map<String, Object?> callDeclineContent(Room room, String callId) {
  final membership = callMembershipEventId(
    room,
    callId,
    excluding: room.client.userID,
  );
  return {
    'msgtype': callDeclineMsgtype,
    'body': 'Call declined',
    'call_id': callId,
    if (membership != null) 'm.relates_to': callReference(membership),
  };
}

Future<void> declineCall(Room room, String callId) =>
    room.sendEvent(callDeclineContent(room, callId));
