import 'dart:async';

import 'package:matrix/matrix.dart';

import '../errors/caught_errors.dart';
import 'matrixrtc/call_member_state.dart';

enum CallLiveness { live, gone, unknown }

const callLivenessTimeout = Duration(seconds: 5);

Future<CallLiveness> checkCallLiveness(
  Client client, {
  required String roomId,
  required String callId,
  required String callerId,
  Duration timeout = callLivenessTimeout,
}) async {
  if (callerId.isEmpty) return CallLiveness.unknown;
  try {
    final content = await client
        .getRoomStateWithKey(roomId, callMemberEventType, callerId)
        .timeout(timeout);
    return parseRtcMemberships(
          content,
          includeExpired: true,
        ).any((m) => m.callId == callId)
        ? CallLiveness.live
        : CallLiveness.gone;
  } catch (e, s) {
    if (e is MatrixException && e.error == MatrixError.M_NOT_FOUND) {
      return CallLiveness.gone;
    }
    reportCaught('check call liveness', e, s);
    return CallLiveness.unknown;
  }
}
