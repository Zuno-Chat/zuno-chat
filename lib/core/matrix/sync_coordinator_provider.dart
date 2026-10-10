import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../calls/active_call_provider.dart';
import '../calls/platform/system_ring.dart';
import '../location/live_location_sharing.dart';
import '../notifications/notification_delivery_mode.dart';
import '../settings/app_preferences_provider.dart';
import 'connectivity_provider.dart';
import 'matrix_client_provider.dart';
import 'sync_coordinator.dart';
import 'zuno_client.dart';

final syncCoordinatorProvider = Provider<SyncCoordinator?>((ref) {
  final client = ref.watch(matrixClientProvider);
  return client is ZunoClient ? client.syncCoordinator : null;
});

final syncReasonsProvider = Provider<void>((ref) {
  final sync = ref.watch(syncCoordinatorProvider);
  if (sync == null) return;

  void foreground(AppLifecycleState? state) =>
      sync.set(SyncReason.foreground, isAppInForeground(state));
  foreground(WidgetsBinding.instance.lifecycleState);
  final lifecycle = AppLifecycleListener(onStateChange: foreground);

  ref.listen(
    activeCallProvider,
    (_, call) => sync.set(SyncReason.call, call != null),
    fireImmediately: true,
  );

  final ringing = SystemRing.instance.ringing;
  void ring() => sync.set(SyncReason.ring, ringing.value != null);
  ringing.addListener(ring);
  ring();

  ValueListenable<bool>? sharing;
  void share() => sync.set(SyncReason.liveShare, sharing?.value ?? false);
  ref.listen(liveLocationSharingProvider, (_, live) {
    sharing?.removeListener(share);
    sharing = live.needsSync..addListener(share);
    share();
  }, fireImmediately: true);

  ref.listen(
    notificationDeliveryModeProvider,
    (_, mode) => sync.set(
      SyncReason.delivery,
      mode == NotificationDeliveryMode.backgroundService,
    ),
    fireImmediately: true,
  );

  final network = ref
      .watch(networkAvailabilityProvider)
      .listen(sync.setNetworkAvailable);

  ref.onDispose(() {
    lifecycle.dispose();
    ringing.removeListener(ring);
    sharing?.removeListener(share);
    network.cancel();
    for (final reason in SyncReason.values) {
      sync.set(reason, false);
    }
  });
});
