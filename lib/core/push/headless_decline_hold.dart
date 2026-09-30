import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../calls/matrixrtc/call_decline.dart';
import '../calls/notifications/call_notification_service.dart';
import '../calls/platform/incoming_call_presenter.dart';
import '../platform/platform_capabilities.dart';
import 'headless_push_runner.dart';

Future<void> awaitHeadlessDecline(
  HeadlessPushRunner runner, {
  IncomingCallPresenter? presenter,
}) async {
  final ring = presenter ?? incomingCallPresenterFor(ambientCapabilities);
  if (!CallNotificationService.instance.claimDeclinePortIfUnclaimed()) return;
  final finished = Completer<HeadlessCallDecline?>();
  void finish(HeadlessCallDecline? decline) {
    if (!finished.isCompleted) finished.complete(decline);
  }

  final sub = CallNotificationService.instance.onHeadlessDecline.listen(finish);
  final poll = Timer.periodic(const Duration(seconds: 1), (_) async {
    if (finished.isCompleted) return;
    if (!CallNotificationService.instance.stillHoldsDeclinePort()) {
      debugPrint('zuno/push: main isolate took over, headless standing down');
      finish(null);
      return;
    }
    if (await ring.activeRing() != null) return;
    finish(null);
  });
  try {
    final decline = await finished.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () => null,
    );
    if (decline == null) return;
    await runner.withClient((client) async {
      final room = client.getRoomById(decline.roomId);
      if (room != null) await declineCall(room, decline.callId);
    });
    await ring.cancelIncoming(roomId: decline.roomId, callId: decline.callId);
  } finally {
    poll.cancel();
    await sub.cancel();
    CallNotificationService.instance.releaseDeclinePort();
  }
}
