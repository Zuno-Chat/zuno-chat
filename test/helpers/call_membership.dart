import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/matrixrtc/call_member_state.dart';

import 'fake_matrix.dart';

void joinCall(
  Room room, {
  required String userId,
  required String deviceId,
  String callId = 'c1',
  String kind = 'voice',
  Duration expiresIn = const Duration(seconds: 30),
}) => room.setState(
  buildTestEvent(
    room,
    eventId: '\$member-$userId-$deviceId-$callId',
    senderId: userId,
    stateKey: userId,
    type: callMemberEventType,
    content: {
      'memberships': [
        RtcMembership(
          callId: callId,
          deviceId: deviceId,
          kind: kind,
          expiresAtMs: DateTime.now().add(expiresIn).millisecondsSinceEpoch,
          fociActive: const {},
        ).toJson(),
      ],
    },
  ),
);
