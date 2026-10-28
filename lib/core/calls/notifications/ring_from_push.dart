import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../errors/caught_errors.dart';
import '../active_call_marker.dart';
import '../matrixrtc/incoming_call.dart';
import '../matrixrtc/resolved_call_ids_store.dart';
import '../platform/incoming_call_presenter.dart';
import '../platform/system_ring.dart';
import 'ring_notification.dart';
import 'ring_over_lines.dart';
import 'ringing_call_store.dart';

const _ringSummaryGrace = Duration(seconds: 3);

Future<void> endRingForCallSummary(
  Event event,
  IncomingCallPresenter presenter,
) async {
  final callId = event.content.tryGet<String>('call_id');
  if (callId != null) {
    await markCallResolved(callId);
    final ringAge = await _ringAge(callId);
    if (ringAge != null && ringAge < _ringSummaryGrace) {
      await Future<void>.delayed(_ringSummaryGrace - ringAge);
    }
  }
  await presenter.cancelIncoming(roomId: event.room.id, callId: callId);
}

Future<bool> ringFromPush(
  IncomingCall call,
  IncomingCallPresenter presenter,
) async {
  final callId = call.callId;
  if (isCallActiveInProcess()) {
    if (kDebugMode) {
      debugPrint('zuno/push: already on a call, not ringing $callId');
    }
    return false;
  }
  if (await isCallResolved(callId)) {
    if (kDebugMode) {
      debugPrint('zuno/push: $callId already resolved, not ringing');
    }
    await presenter.cancelIncoming(roomId: call.room.id, callId: callId);
    return false;
  }
  final heldHere = await _whileRinging(
    SystemRing.instance.ringing.value?.callId,
    callId,
  );
  if (heldHere != null) return heldHere;
  final ringingNow = presenter.activeRing();
  final ringingElsewhere = await _whileRinging(
    (await ringingNow)?.callId,
    callId,
  );
  if (ringingElsewhere ?? false) await takeDownLinesUnderRing(call);
  if (ringingElsewhere != null) return ringingElsewhere;
  SystemRing.instance.set(roomId: call.room.id, callId: callId);
  var outcome = RingOutcome.unavailable;
  try {
    outcome = await postRingNotification(
      call,
      presenter: presenter,
      ringingNow: ringingNow,
    );
  } finally {
    if (outcome != RingOutcome.shown) SystemRing.instance.clear(callId);
  }
  if (outcome != RingOutcome.shown) return false;
  if (kDebugMode) {
    debugPrint('zuno/push: ring notification posted for $callId');
  }
  return true;
}

Future<bool?> _whileRinging(String? ringing, String callId) async {
  if (ringing == null) return null;
  if (ringing == callId) {
    if (kDebugMode) debugPrint('zuno/push: $callId already rings');
    return true;
  }
  if (await isCallResolved(ringing)) return null;
  if (kDebugMode) {
    debugPrint('zuno/push: $ringing is ringing, not ringing $callId');
  }
  return false;
}

Future<Duration?> _ringAge(String callId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return ringAgeFor(prefs, callId);
  } catch (e, s) {
    reportCaught('push ring age read', e, s);
    return null;
  }
}
