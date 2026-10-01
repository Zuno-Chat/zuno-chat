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

String callDeclineTxid(String callId) => 'zuno-decline-$callId';

Future<String?> _sendDecline(Room room, String callId) => room.sendEvent(
  callDeclineContent(room, callId),
  txid: callDeclineTxid(callId),
);

Future<void> declineCall(Room room, String callId) =>
    _sendDecline(room, callId);

class CallDeclineNotSent implements Exception {
  const CallDeclineNotSent(this.callId);

  final String callId;

  @override
  String toString() => 'CallDeclineNotSent($callId)';
}

Future<void> declineCallOrFail(Room room, String callId) async {
  final sent = await _sendDecline(room, callId);
  if (sent == null) throw CallDeclineNotSent(callId);
}
