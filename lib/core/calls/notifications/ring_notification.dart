import '../../matrix/room_user_display.dart';
import '../../platform/platform_capabilities.dart';
import '../matrixrtc/incoming_call.dart';
import '../models/call_kind.dart';
import '../platform/incoming_call_presenter.dart';
import 'caller_avatar.dart';

Future<void> postRingNotification(
  IncomingCall call, {
  bool allowNetwork = false,
  IncomingCallPresenter? presenter,
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
  await ring.showIncoming(
    callerName: caller.calcDisplayname(),
    callerId: call.callerId,
    isVideo: call.kind == CallKind.video,
    roomId: call.room.id,
    callId: call.callId,
    isGroupCall: !call.room.isDirectChat,
    avatarBytes: avatarBytes,
  );
}
