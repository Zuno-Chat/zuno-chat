import 'package:flutter/foundation.dart' show Listenable, debugPrint;
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
import 'unified_push_delivery_provider.dart' show UnifiedPushStatus;

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
  final watched = Listenable.merge([
    fcmDeliveryProvider.status,
    fcmDeliveryProvider.removed,
    unifiedPushDeliveryProvider.status,
    unifiedPushDeliveryProvider.removed,
    unifiedPushDeliveryProvider.distributorBatteryRestricted,
    apnsDeliveryProvider.status,
    apnsDeliveryProvider.dropped,
  ]);
  watched.addListener(rebuild);
  ref.onDispose(() => watched.removeListener(rebuild));

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
    fcmRemoved: fcmDeliveryProvider.removed.value,
    unifiedPushRemoved: unifiedPushDeliveryProvider.removed.value,
  );
});

final dismissedDeliveryFailureProvider =
    NotifierProvider<DismissedDeliveryFailureNotifier, DeliveryFailure?>(
      DismissedDeliveryFailureNotifier.new,
    );

class DismissedDeliveryFailureNotifier extends Notifier<DeliveryFailure?> {
  @override
  DeliveryFailure? build() {
    final statuses = Listenable.merge([
      fcmDeliveryProvider.status,
      unifiedPushDeliveryProvider.status,
      apnsDeliveryProvider.status,
      apnsDeliveryProvider.dropped,
    ]);
    statuses.addListener(_clearOnceDelivering);
    ref.onDispose(() => statuses.removeListener(_clearOnceDelivering));
    return null;
  }

  void _clearOnceDelivering() {
    final delivering =
        fcmDeliveryProvider.status.value == FcmStatus.ready ||
        unifiedPushDeliveryProvider.status.value == UnifiedPushStatus.ready ||
        (apnsDeliveryProvider.status.value == ApnsStatus.ready &&
            apnsDeliveryProvider.dropped.value == 0);
    if (delivering) state = null;
  }

  void dismiss(DeliveryFailure failure) => state = failure;

  void clear() => state = null;
}

bool deliveryFailureIsDismissed(
  DeliveryFailure failure,
  DeliveryFailure? dismissed,
) =>
    dismissed != null &&
    dismissed.message == failure.message &&
    dismissed.action == failure.action;
