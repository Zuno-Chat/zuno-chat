import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_store.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart'
    show RingingCallInfo;
import 'package:zuno/core/calls/notifications/ringing_call_store.dart';

import 'native_method_calls.dart';

const testRingingCall = (
  roomId: '!room:example.org',
  callId: 'call1',
  callerId: '@bob:example.org',
  isVideo: true,
);

Future<void> saveRingingCall(SharedPreferences prefs, RingingCallInfo call) =>
    prefs.setString(
      ringingCallKey,
      jsonEncode({
        'roomId': call.roomId,
        'callId': call.callId,
        'callerId': call.callerId,
        'isVideo': call.isVideo,
        'postedAt': clock.now().millisecondsSinceEpoch,
      }),
    );

class FakeNativeRing extends RecordedMethodCalls {
  RingingCallInfo? ringing;
  bool showFails = false;

  Future<void> ringNatively(RingingCallInfo call) async {
    ringing = call;
    await rememberRang(call);
  }

  Future<void> rememberRang(RingingCallInfo call) async =>
      saveRingingCall(await SharedPreferences.getInstance(), call);

  Future<Object?> _reply(MethodCall call) async {
    final args = call.arguments is Map ? call.arguments as Map : const {};
    final callId = args['callId'] as String?;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final remembered = readRingingCall(prefs);
    switch (call.method) {
      case 'showIncomingCallStyle':
        if (callId == null || showFails) return 'unavailable';
        if (ringing?.callId == callId) return 'ringing';
        if (remembered?.callId == callId) return 'rangHere';
        if (ringing case final other?
            when !await isCallResolved(other.callId)) {
          return 'busy';
        }
        await ringNatively((
          roomId: args['roomId'] as String,
          callId: callId,
          callerId: args['callerId'] as String? ?? '',
          isVideo: args['isVideo'] == true,
        ));
        return 'shown';
      case 'cancelIncomingCallStyle':
        if (callId == null || ringing?.callId == callId) ringing = null;
        if (callId == null || remembered?.callId == callId) {
          await prefs.remove(ringingCallKey);
        }
        return null;
      case 'activeRing':
        final active = ringing;
        if (active == null) return null;
        return {
          'roomId': active.roomId,
          'callId': active.callId,
          'callerId': active.callerId,
          'isVideo': active.isVideo,
        };
    }
    return null;
  }
}

FakeNativeRing installFakeCallStyleChannel() {
  final fake = FakeNativeRing();
  return recordInto(
    const MethodChannel('zuno/call_style'),
    fake,
    reply: fake._reply,
  );
}

extension CallStyleReadings on RecordedMethodCalls {
  MethodCall get lastShow => named('showIncomingCallStyle').last;
}
