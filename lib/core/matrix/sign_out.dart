import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import '../calls/active_call_provider.dart';
import '../calls/end_call.dart';
import '../calls/matrixrtc/call_session.dart';
import '../errors/caught_errors.dart';
import '../l10n/l10n.dart';
import '../location/live_location_sharing.dart';
import '../notifications/notification_delivery_provider.dart';
import 'connectivity_provider.dart';
import 'matrix_client_provider.dart';

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

Future<void> signOutThisDeviceOrExplain(
  BuildContext context,
  WidgetRef ref,
) async {
  if (ref.read(isOfflineProvider).value ?? false) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.matrixSignOutOffline)));
    return;
  }
  await signOutThisDevice(
    ref.read(matrixClientProvider),
    windDown: ref.read(signOutWindDownProvider),
  );
}

Future<void> signOutThisDevice(
  Client client, {
  required SignOutWindDown windDown,
  Future<void> Function(Client client) stopDelivery =
      stopAllNotificationDelivery,
}) async {
  await windDown();
  await stopDelivery(client);
  try {
    await client.logout();
  } catch (e, s) {
    reportCaught('sign out', e, s);
  }
}
