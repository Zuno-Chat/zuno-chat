import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
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

bool deliveryModeEnabled(
  NotificationDeliveryMode mode, {
  required FcmAvailability? fcm,
}) =>
    mode != NotificationDeliveryMode.fcm ||
    switch (fcm) {
      FcmAvailability.available ||
      FcmAvailability.unknown ||
      FcmAvailability.updateRequired => true,
      null ||
      FcmAvailability.disabled ||
      FcmAvailability.unavailable ||
      FcmAvailability.notConfigured => false,
    };

DeliveryModeChoice deliveryModeChoice(
  AppLocalizations l10n,
  NotificationDeliveryMode mode, {
  required FcmAvailability? fcm,
}) => (
  enabled: deliveryModeEnabled(mode, fcm: fcm),
  subtitle: mode != NotificationDeliveryMode.fcm
      ? mode.description(l10n)
      : switch (fcm) {
          null => l10n.pushCheckingDevice,
          FcmAvailability.available ||
          FcmAvailability.unknown => mode.description(l10n),
          FcmAvailability.updateRequired => l10n.notificationsPlayUpdateOffered,
          FcmAvailability.disabled => l10n.notificationsPlayTurnedOffHint,
          FcmAvailability.unavailable => l10n.notificationsPlayMissingSubtitle,
          FcmAvailability.notConfigured =>
            l10n.notificationsGoogleNotIncludedSubtitle,
        },
);
