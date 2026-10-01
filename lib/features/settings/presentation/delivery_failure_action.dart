import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/matrix/matrix_client_provider.dart';
import '../../../core/notifications/apns_delivery_provider.dart';
import '../../../core/notifications/background_sync_service.dart';
import '../../../core/notifications/delivery_auto_fallback.dart';
import '../../../core/notifications/delivery_failure.dart';
import '../../../core/notifications/delivery_failure_provider.dart';
import '../../../core/notifications/fcm_delivery_provider.dart';
import '../../../core/notifications/notification_delivery_mode.dart';
import '../../../core/notifications/notification_delivery_provider.dart';
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
        await BackgroundSyncService.instance.openAppSettings(distributor);
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
  }
}
