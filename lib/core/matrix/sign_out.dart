import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import '../calls/active_call_provider.dart';
import '../calls/end_call.dart';
import '../calls/matrixrtc/call_session.dart';
import '../location/live_location_sharing.dart';
import '../notifications/notification_delivery_provider.dart';

const _liveShareStopBound = Duration(seconds: 5);

typedef SignOutWindDown = Future<void> Function();

final signOutWindDownProvider = Provider<SignOutWindDown>(
  (ref) =>
      () => windDownBeforeSignOut(
        activeCall: ref.read(activeCallProvider),
        liveLocation: ref.read(liveLocationSharingProvider),
      ),
);

Future<void> windDownBeforeSignOut({
  required CallSession? activeCall,
  required LiveLocationSharing liveLocation,
}) async {
  await endCall(activeCall);
  await liveLocation.stopAll(within: _liveShareStopBound);
}

Future<void> signOutThisDevice(
  Client client, {
  required SignOutWindDown windDown,
  Future<void> Function(Client client) stopDelivery =
      stopAllNotificationDelivery,
}) async {
  await windDown();
  await stopDelivery(client);
  await client.logout();
}
