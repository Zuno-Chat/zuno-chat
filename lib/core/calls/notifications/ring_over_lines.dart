import 'package:matrix/matrix.dart';

import '../../errors/best_effort.dart';
import '../../notifications/messages/message_notifications.dart';
import '../../notifications/settings/notification_preview.dart';
import '../../platform/platform_capabilities.dart';
import '../matrixrtc/incoming_call.dart';
import '../platform/incoming_call_presenter.dart';

Future<bool> ringStandsInFor(
  Event locked,
  IncomingCallPresenter presenter,
) async {
  final ringing = await presenter.activeRing();
  return ringing != null &&
      ringing.roomId == locked.room.id &&
      ringing.callerId == locked.senderId;
}

Future<void> takeDownLinesUnderRing(IncomingCall call) async {
  if (ambientCapabilities.callKit) return;
  await runBestEffort(
    () async => MessageNotifications.instance.retractPlaceholdersFrom(
      call.room.id,
      call.callerId,
      preview: await currentNotificationPreview(),
    ),
    label: 'ring line takedown',
  );
}
