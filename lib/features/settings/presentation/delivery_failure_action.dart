import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/platform/background_restrictions.dart';
import '../../../core/push/apns/apns_delivery_provider.dart';
import '../../../core/push/delivery/delivery_auto_fallback.dart';
import '../../../core/push/delivery/delivery_failure.dart';
import '../../../core/push/delivery/delivery_failure_provider.dart';
import '../../../core/push/delivery/notification_delivery_mode.dart';
import '../../../core/push/fcm/fcm_delivery_provider.dart';
import '../../../core/push/ring/ring_registration.dart';
import '../../../core/push/unified_push/unified_push_delivery_provider.dart';
import '../../../core/settings/app_preferences_provider.dart';
import 'notification_delivery_page.dart';

Future<void> runDeliveryFailureAction(
  BuildContext context,
  WidgetRef ref,
  DeliveryFailure failure,
) async {
  ref.read(dismissedDeliveryFailureProvider.notifier).clear();
  switch (failure.action) {
    case DeliveryFailureAction.openSettings:
      await ref.read(autoSelectedDeliveryModeProvider.notifier).acknowledge();
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const NotificationDeliveryPage()),
      );
    case DeliveryFailureAction.openDistributorSettings:
      final distributor = unifiedPushDeliveryProvider.savedDistributor;
      if (distributor != null) {
        await BackgroundRestrictions.instance.openAppSettings(distributor);
      }
    case DeliveryFailureAction.switchToUnifiedPush:
      await ref
          .read(notificationDeliveryModeProvider.notifier)
          .set(NotificationDeliveryMode.unifiedPush);
      await unifiedPushDeliveryProvider.discoverDistributorsIfNeeded();
    case DeliveryFailureAction.switchToBackgroundService:
      await ref
          .read(notificationDeliveryModeProvider.notifier)
          .set(NotificationDeliveryMode.backgroundService);
    case DeliveryFailureAction.updatePlayServices:
    case DeliveryFailureAction.turnOnPlayServices:
      await fcmDeliveryProvider.fixPlayServices(ref.read(matrixClientProvider));
    case DeliveryFailureAction.retry:
      final client = ref.read(matrixClientProvider);
      switch (ref.read(notificationDeliveryModeProvider)) {
        case NotificationDeliveryMode.fcm:
          await fcmDeliveryProvider.registerNow(client);
        case NotificationDeliveryMode.unifiedPush:
          await unifiedPushDeliveryProvider.registerNow(client);
        case NotificationDeliveryMode.apns:
          await apnsDeliveryProvider.registerNow(client);
        case NotificationDeliveryMode.backgroundService:
          break;
      }
    case DeliveryFailureAction.retryCalls:
      await ref
          .read(ringRegistrationProvider)
          .registerNow(ref.read(matrixClientProvider));
  }
}
