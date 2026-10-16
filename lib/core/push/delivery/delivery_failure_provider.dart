import 'package:flutter/foundation.dart' show Listenable;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unifiedpush_platform_interface/unifiedpush_platform_interface.dart';

import '../../errors/caught_errors.dart';
import '../../notifications/settings/notifications_allowed_provider.dart';
import '../../platform/platform_capabilities.dart';
import '../../settings/app_preferences_provider.dart';
import '../apns/apns_delivery_provider.dart';
import '../fcm/fcm_delivery_provider.dart';
import '../unified_push/unified_push_delivery_provider.dart'
    show UnifiedPushStatus;
import '../voip/voip_registration.dart';
import 'delivery_auto_fallback.dart';
import 'delivery_failure.dart';
import 'notification_delivery_mode.dart';
import 'notification_delivery_provider.dart';

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
        return (await UnifiedPushPlatform.instance.getDistributors(const []))
            .isNotEmpty;
      } catch (e, s) {
        reportCaught('unifiedpush distributors list', e, s);
        return false;
      }
    });

DeliveryFailure? _callsFailure(Ref ref) {
  if (!ref.watch(platformCapabilitiesProvider).voipRing) return null;
  final registration = ref.watch(voipRegistrationProvider);
  void rebuild() => ref.invalidateSelf();
  registration.state.addListener(rebuild);
  ref.onDispose(() => registration.state.removeListener(rebuild));
  return callsDeliveryFailure(registration.state.value);
}

final deliveryFailureProvider = Provider<DeliveryFailure?>((ref) {
  final calls = _callsFailure(ref);
  if (ref.watch(notificationsAllowedProvider) != true) return calls;
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
      ) ??
      calls;
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
