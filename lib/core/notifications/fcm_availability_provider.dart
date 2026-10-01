import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/platform_capabilities.dart';
import '../push/fcm_bridge.dart';
import 'notification_delivery_mode.dart';

final fcmAvailabilityProvider = FutureProvider.autoDispose<FcmAvailability>((
  ref,
) {
  final offered = ref
      .watch(platformCapabilitiesProvider)
      .deliveryModes
      .contains(NotificationDeliveryMode.fcm);
  if (!offered) return FcmAvailability.unavailable;
  final lifecycle = AppLifecycleListener(onResume: ref.invalidateSelf);
  ref.onDispose(lifecycle.dispose);
  return FcmBridge.instance.availability();
});

typedef DeliveryModeChoice = ({bool enabled, String subtitle});

DeliveryModeChoice deliveryModeChoice(
  NotificationDeliveryMode mode, {
  required FcmAvailability? fcm,
}) {
  if (mode != NotificationDeliveryMode.fcm) {
    return (enabled: true, subtitle: mode.description);
  }
  return switch (fcm) {
    null => (enabled: false, subtitle: 'Checking this device…'),
    FcmAvailability.available ||
    FcmAvailability.unknown => (enabled: true, subtitle: mode.description),
    FcmAvailability.updateRequired => (
      enabled: true,
      subtitle:
          'Google Play services needs an update. Zuno offers the update once '
          'you choose this.',
    ),
    FcmAvailability.disabled => (
      enabled: false,
      subtitle:
          'Google Play services is turned off. Turn it on in your device '
          'settings to use this.',
    ),
    FcmAvailability.unavailable => (
      enabled: false,
      subtitle: 'This device does not have Google Play services.',
    ),
    FcmAvailability.notConfigured => (
      enabled: false,
      subtitle: 'This version of Zuno does not include Google services.',
    ),
  };
}
