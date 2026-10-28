import 'package:flutter/foundation.dart' show debugPrint;

import '../../l10n/l10n.dart';
import '../../notifications/notification_avatar.dart';
import '../../platform/platform_capabilities.dart';
import '../matrixrtc/incoming_call.dart';
import '../matrixrtc/resolved_call_ids_store.dart';
import '../models/call_kind.dart';
import '../platform/incoming_call_presenter.dart';
import '../ring_identity.dart';
import 'call_notification_service.dart' show RingingCallInfo;
import 'ring_over_lines.dart';

Future<RingOutcome> postRingNotification(
  IncomingCall call, {
  bool allowNetwork = false,
  IncomingCallPresenter? presenter,
  Future<RingingCallInfo?>? ringingNow,
  bool waiting = false,
}) async {
  await loadRingIdentity(call, allowNetwork: allowNetwork);
  final identity = ringIdentity(call, deviceLocalizations());
  final avatarBytes = allowNetwork
      ? await fetchNotificationAvatarBytes(call.room.client, identity.avatarUrl)
      : null;
  final ring = presenter ?? incomingCallPresenterFor(ambientCapabilities);
  final outcome = await ring.showIncoming(
    name: identity.name,
    caller: identity.caller,
    callerId: call.callerId,
    isVideo: call.kind == CallKind.video,
    roomId: call.room.id,
    callId: call.callId,
    isGroupCall: !call.room.isDirectChat,
    avatarBytes: avatarBytes,
    ringingNow: ringingNow,
    waiting: waiting,
    ringFor: call.ringFor,
  );
  if (outcome != RingOutcome.shown) return outcome;
  if (!await isCallResolved(call.callId)) {
    await takeDownLinesUnderRing(call);
    return outcome;
  }
  debugPrint('zuno/calls: ${call.callId} ended while ringing, taking it back');
  await ring.cancelIncoming(roomId: call.room.id, callId: call.callId);
  return RingOutcome.filtered;
}
