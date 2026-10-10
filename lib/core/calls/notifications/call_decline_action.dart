import 'package:flutter/foundation.dart' show debugPrint;
import 'package:matrix/matrix.dart';

import '../../errors/best_effort.dart';
import '../../errors/caught_errors.dart';
import '../../notifications/message_notification_action.dart';
import '../../platform/platform_capabilities.dart';
import '../matrixrtc/call_decline.dart';
import '../matrixrtc/resolved_call_ids_store.dart';
import '../platform/incoming_call_presenter.dart';

const callDeclineWakeLock = HeadlessWakeLock(tag: 'call_decline');

Future<void> runHeadlessCallDecline({
  required String roomId,
  required String callId,
  required Future<bool> Function() handOff,
  required Future<Client> Function() clientBuilder,
  IncomingCallPresenter? presenter,
  HeadlessWakeLock wakeLock = callDeclineWakeLock,
  List<Duration> retryDelays = headlessActionRetryDelays,
  Duration handOffPatience = liveHandOffPatience,
  Duration handOffRetryEvery = liveHandOffRetryEvery,
}) async {
  final lock = wakeLock.forRun();
  await lock.acquire();
  Client? client;
  try {
    final ring = presenter ?? incomingCallPresenterFor(ambientCapabilities);
    await runBestEffort(
      () => ring.cancelIncoming(roomId: roomId, callId: callId),
      label: 'stop the ring for a declined call',
    );
    await markCallResolved(callId);
    Future<bool> handOver() => _handedOff(handOff);
    if (await handOver()) return;
    debugPrint('zuno/calls: no running app took the decline of $callId');
    await lock.acquire();
    client = await clientOrPatientHandOff(
      clientBuilder,
      handOff: handOver,
      wakeLock: lock,
      within: handOffPatience,
      every: handOffRetryEvery,
    );
    if (client == null) return;
    final room = client.getRoomById(roomId);
    if (room == null) return;
    await retryNotificationAction(
      () => declineCallOrFail(room, callId),
      retryDelays,
    );
  } catch (e, s) {
    reportCaught('decline a call in the background', e, s);
  } finally {
    await client?.dispose(closeDatabase: false);
    await lock.release();
  }
}

Future<bool> _handedOff(Future<bool> Function() handOff) async {
  try {
    return await handOff();
  } catch (e, s) {
    reportCaught('hand the decline to the app', e, s);
    return false;
  }
}
