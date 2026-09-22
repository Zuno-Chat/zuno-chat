import '../../matrix/room_user_display.dart';
import '../matrixrtc/incoming_call.dart';
import '../models/call_kind.dart';
import 'call_notification_service.dart';
import 'caller_avatar.dart';

Future<void> postRingNotification(
  IncomingCall call, {
  bool allowNetwork = false,
}) async {
  final caller = await resolveRoomUser(
    call.room,
    call.callerId,
    allowNetwork: allowNetwork,
  );
  final avatarBytes = allowNetwork
      ? await fetchCallerAvatarBytes(call.room.client, caller.avatarUrl)
      : null;
  await CallNotificationService.instance.showIncomingCall(
    callerName: caller.calcDisplayname(),
    callerId: call.callerId,
    isVideo: call.kind == CallKind.video,
    roomId: call.room.id,
    callId: call.callId,
    isGroupCall: !call.room.isDirectChat,
    avatarBytes: avatarBytes,
  );
}
