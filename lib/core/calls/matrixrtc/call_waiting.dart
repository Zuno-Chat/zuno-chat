import 'call_decline.dart';
import 'incoming_call.dart';

Future<void> autoDeclineIncomingCall(IncomingCall call) =>
    declineCall(call.room, call.callId);
