import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unifiedpush/unifiedpush.dart';

import '../platform/platform_capabilities.dart';
import '../settings/app_preferences_provider.dart';
import 'apns_delivery_provider.dart';
import 'delivery_auto_fallback.dart';
import 'delivery_failure.dart';
import 'fcm_delivery_provider.dart';
import 'notification_delivery_mode.dart';
import 'notification_delivery_provider.dart';
import 'notification_permission_provider.dart';

final unifiedPushDistributorInstalledProvider =
    FutureProvider.autoDispose<bool>((ref) async {
      final offered = ref
          .watch(platformCapabilitiesProvider)
          .deliveryModes
          .contains(NotificationDeliveryMode.unifiedPush);
      if (!offered) return false;
      final lifecycle = AppLifecycleListener(onResume: ref.invalidateSelf);
      ref.onDispose(lifecycle.dispose);
      try {
        return (await UnifiedPush.getDistributors()).isNotEmpty;
      } catch (e) {
        debugPrint('zuno/push: could not list UnifiedPush distributors ($e)');
        return false;
      }
    });

final deliveryFailureProvider = Provider<DeliveryFailure?>((ref) {
  if (ref.watch(notificationsAllowedProvider) != true) return null;
  final mode = ref.watch(notificationDeliveryModeProvider);
  final autoSelected = ref.watch(autoSelectedDeliveryModeProvider);
  final distributorInstalled = mode == NotificationDeliveryMode.fcm
      ? ref.watch(unifiedPushDistributorInstalledProvider).value
      : null;

  void rebuild() => ref.invalidateSelf();
  fcmDeliveryProvider.status.addListener(rebuild);
  unifiedPushDeliveryProvider.status.addListener(rebuild);
  apnsDeliveryProvider.status.addListener(rebuild);
  apnsDeliveryProvider.dropped.addListener(rebuild);
  unifiedPushDeliveryProvider.distributorBatteryRestricted.addListener(rebuild);
  ref.onDispose(() {
    fcmDeliveryProvider.status.removeListener(rebuild);
    unifiedPushDeliveryProvider.status.removeListener(rebuild);
    apnsDeliveryProvider.status.removeListener(rebuild);
    apnsDeliveryProvider.dropped.removeListener(rebuild);
    unifiedPushDeliveryProvider.distributorBatteryRestricted.removeListener(
      rebuild,
    );
  });

  return notificationDeliveryFailure(
    mode: mode,
    fcm: fcmDeliveryProvider.status.value,
    unifiedPush: unifiedPushDeliveryProvider.status.value,
    apns: apnsDeliveryProvider.status.value,
    apnsDropped: apnsDeliveryProvider.dropped.value,
    distributorBatteryRestricted:
        unifiedPushDeliveryProvider.distributorBatteryRestricted.value,
    distributor: unifiedPushDeliveryProvider.savedDistributor,
    distributorInstalled: distributorInstalled,
    autoSelected: autoSelected,
  );
});

final dismissedDeliveryFailureProvider =
    NotifierProvider<DismissedDeliveryFailureNotifier, DeliveryFailure?>(
      DismissedDeliveryFailureNotifier.new,
    );

class DismissedDeliveryFailureNotifier extends Notifier<DeliveryFailure?> {
  @override
  DeliveryFailure? build() => null;

  void dismiss(DeliveryFailure failure) => state = failure;
}

bool deliveryFailureIsDismissed(
  DeliveryFailure failure,
  DeliveryFailure? dismissed,
) =>
    dismissed != null &&
    dismissed.message == failure.message &&
    dismissed.action == failure.action;
