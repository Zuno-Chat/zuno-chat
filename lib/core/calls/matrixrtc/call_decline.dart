import 'package:matrix/matrix.dart';

import 'call_summary_message.dart';

Future<void> declineCall(Room room, String callId) => room.sendEvent({
  'msgtype': callDeclineMsgtype,
  'body': 'Call declined',
  'call_id': callId,
});
