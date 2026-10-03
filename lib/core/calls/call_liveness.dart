import 'dart:async';

import 'package:matrix/matrix.dart';

import 'matrixrtc/call_member_state.dart';
import 'models/call_kind.dart';

enum CallLiveness { live, gone, unknown }

const callLivenessTimeout = Duration(seconds: 5);

typedef RawMembership = ({String callId, CallKind kind, int createdTs});

List<RawMembership> rawMemberships(Map<String, Object?>? content) {
  final memberships = content?['memberships'];
  if (memberships is! List) return const [];
  return [
    for (final membership in memberships)
      if (membership is Map)
        if (membership['call_id'] case final String callId)
          (
            callId: callId,
            kind: membership['kind'] == 'video'
                ? CallKind.video
                : CallKind.voice,
            createdTs: switch (membership['created_ts']) {
              final int at => at,
              _ => 0,
            },
          ),
  ];
}

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
    return rawMemberships(content).any((m) => m.callId == callId)
        ? CallLiveness.live
        : CallLiveness.gone;
  } on MatrixException catch (e) {
    return e.error == MatrixError.M_NOT_FOUND
        ? CallLiveness.gone
        : CallLiveness.unknown;
  } catch (_) {
    return CallLiveness.unknown;
  }
}
