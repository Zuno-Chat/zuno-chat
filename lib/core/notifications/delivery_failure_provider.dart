import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/app_preferences_provider.dart';
import 'delivery_auto_fallback.dart';
import 'delivery_failure.dart';
import 'fcm_delivery_provider.dart';
import 'notification_delivery_provider.dart';

final deliveryFailureProvider = Provider<DeliveryFailure?>((ref) {
  final mode = ref.watch(notificationDeliveryModeProvider);
  final autoSelected = ref.watch(autoSelectedDeliveryModeProvider);

  void rebuild() => ref.invalidateSelf();
  fcmDeliveryProvider.status.addListener(rebuild);
  unifiedPushDeliveryProvider.status.addListener(rebuild);
  unifiedPushDeliveryProvider.distributorBatteryRestricted.addListener(rebuild);
  ref.onDispose(() {
    fcmDeliveryProvider.status.removeListener(rebuild);
    unifiedPushDeliveryProvider.status.removeListener(rebuild);
    unifiedPushDeliveryProvider.distributorBatteryRestricted.removeListener(
      rebuild,
    );
  });

  return notificationDeliveryFailure(
    mode: mode,
    fcm: fcmDeliveryProvider.status.value,
    unifiedPush: unifiedPushDeliveryProvider.status.value,
    distributorBatteryRestricted:
        unifiedPushDeliveryProvider.distributorBatteryRestricted.value,
    distributor: unifiedPushDeliveryProvider.savedDistributor,
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
