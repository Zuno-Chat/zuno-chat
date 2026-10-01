import 'package:flutter/foundation.dart' show debugPrint;

import '../../matrix/room_title.dart';
import '../../matrix/room_user_display.dart';
import '../../platform/platform_capabilities.dart';
import '../matrixrtc/incoming_call.dart';
import '../matrixrtc/resolved_call_ids_store.dart';
import '../models/call_kind.dart';
import '../platform/incoming_call_presenter.dart';
import 'call_notification_service.dart' show RingingCallInfo;
import 'caller_avatar.dart';

Future<RingOutcome> postRingNotification(
  IncomingCall call, {
  bool allowNetwork = false,
  IncomingCallPresenter? presenter,
  Future<RingingCallInfo?>? ringingNow,
}) async {
  final caller = await resolveRoomUser(
    call.room,
    call.callerId,
    allowNetwork: allowNetwork,
  );
  final avatarBytes = allowNetwork
      ? await fetchCallerAvatarBytes(call.room.client, caller.avatarUrl)
      : null;
  final ring = presenter ?? incomingCallPresenterFor(ambientCapabilities);
  final outcome = await ring.showIncoming(
    callerName: caller.calcDisplayname(),
    callerId: call.callerId,
    isVideo: call.kind == CallKind.video,
    roomId: call.room.id,
    callId: call.callId,
    isGroupCall: !call.room.isDirectChat,
    roomName: call.room.isDirectChat ? null : roomTitle(call.room),
    avatarBytes: avatarBytes,
    ringingNow: ringingNow,
  );
  if (outcome != RingOutcome.shown) return outcome;
  if (!await isCallResolved(call.callId)) return outcome;
  debugPrint('zuno/calls: ${call.callId} ended while ringing, taking it back');
  await ring.cancelIncoming(roomId: call.room.id, callId: call.callId);
  return RingOutcome.filtered;
}
