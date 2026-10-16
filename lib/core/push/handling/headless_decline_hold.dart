import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../async/live_isolate_route.dart';
import '../../calls/matrixrtc/call_decline.dart';
import '../../calls/matrixrtc/resolved_call_ids_store.dart';
import '../../calls/platform/incoming_call_presenter.dart';
import '../../matrix/client_lease.dart';
import '../../notifications/local_notifications.dart';
import '../../platform/platform_capabilities.dart';
import 'headless_push_runner.dart';

const declineGrace = Duration(seconds: 5);
const declinePollEvery = Duration(seconds: 3);
const _longestRing = Duration(seconds: 45);

Future<void> awaitHeadlessDecline(
  HeadlessPushRunner runner, {
  IncomingCallPresenter? presenter,
}) async {
  final ring = presenter ?? incomingCallPresenterFor(ambientCapabilities);
  final notifications = LocalNotifications.instance;
  if (!await notifications.claimDeclinePortUnlessLive()) return;
  final finished = Completer<HeadlessCallDecline?>();
  void finish(HeadlessCallDecline? decline) {
    if (!finished.isCompleted) finished.complete(decline);
  }

  final sub = notifications.onHeadlessDecline.listen(finish);
  Timer? grace;
  var checking = false;
  final poll = Timer.periodic(declinePollEvery, (_) async {
    if (finished.isCompleted || checking) return;
    if (!notifications.stillHoldsDeclinePort()) {
      debugPrint('zuno/push: main isolate took over, headless standing down');
      finish(null);
      return;
    }
    checking = true;
    final bool ringing;
    try {
      ringing = await ring.activeRing() != null;
    } finally {
      checking = false;
    }
    if (ringing) {
      grace?.cancel();
      grace = null;
      return;
    }
    grace ??= Timer(declineGrace, () => finish(null));
  });
  try {
    final decline = await finished.future.timeout(
      _longestRing,
      onTimeout: () => null,
    );
    if (decline == null) return;
    await ring.cancelIncoming(roomId: decline.roomId, callId: decline.callId);
    await markCallResolved(decline.callId);
    if (await _sendDecline(runner, notifications, decline)) decline.finished();
  } finally {
    poll.cancel();
    grace?.cancel();
    await sub.cancel();
    notifications.releaseDeclinePort();
  }
}

Future<bool> _sendDecline(
  HeadlessPushRunner runner,
  LocalNotifications notifications,
  HeadlessCallDecline decline,
) async {
  try {
    await runner.withClient((client) async {
      final room = client.getRoomById(decline.roomId);
      if (room != null) await declineCallOrFail(room, decline.callId);
    });
    return true;
  } on ClientLeaseDenied {
    debugPrint('zuno/push: the app holds the client, handing it the decline');
    notifications.releaseDeclinePort();
    return handOffToLiveIsolate(declinePortName, {
      'roomId': decline.roomId,
      'callId': decline.callId,
    });
  }
}
