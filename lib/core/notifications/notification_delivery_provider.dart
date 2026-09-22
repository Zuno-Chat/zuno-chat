import 'package:flutter/foundation.dart' show debugPrint;
import 'package:matrix/matrix.dart';

import 'background_sync_delivery_provider.dart';
import 'fcm_delivery_provider.dart';
import 'notification_delivery_mode.dart';
import 'unified_push_delivery_provider.dart';

abstract class NotificationDeliveryProvider {
  Future<void> start(Client client);

  Future<void> stop(Client client);
}

final _backgroundSync = BackgroundSyncDeliveryProvider();

final unifiedPushDeliveryProvider = UnifiedPushDeliveryProvider();

void bindAppStateToPushDelivery({
  required String? Function() currentlyOpenRoomId,
  required bool Function() isAppSyncing,
}) {
  for (final runner in [
    fcmDeliveryProvider.runner,
    unifiedPushDeliveryProvider.runner,
  ]) {
    runner
      ..currentlyOpenRoomId = currentlyOpenRoomId
      ..isAppSyncing = isAppSyncing;
  }
}

Future<void> stopAllNotificationDelivery(Client client) async {
  for (final mode in NotificationDeliveryMode.values) {
    try {
      await notificationDeliveryProviderFor(mode).stop(client);
    } catch (_) {}
  }
}

NotificationDeliveryProvider notificationDeliveryProviderFor(
  NotificationDeliveryMode mode,
) {
  return switch (mode) {
    NotificationDeliveryMode.backgroundService => _backgroundSync,
    NotificationDeliveryMode.unifiedPush => unifiedPushDeliveryProvider,
    NotificationDeliveryMode.fcm => fcmDeliveryProvider,
  };
}

Future<void> retryFailedDelivery(
  Client client,
  NotificationDeliveryMode mode,
) async {
  try {
    switch (mode) {
      case NotificationDeliveryMode.fcm:
        await fcmDeliveryProvider.retryIfFailed(client);
      case NotificationDeliveryMode.unifiedPush:
        await unifiedPushDeliveryProvider.retryIfFailed(client);
      case NotificationDeliveryMode.backgroundService:
        break;
    }
  } catch (e) {
    debugPrint('zuno/push: retry of ${mode.name} delivery failed: $e');
  }
}

Future<void> recheckDelivery(
  Client client,
  NotificationDeliveryMode mode,
) async {
  try {
    switch (mode) {
      case NotificationDeliveryMode.fcm:
        await fcmDeliveryProvider.recheckRegistration(client);
      case NotificationDeliveryMode.unifiedPush:
        await unifiedPushDeliveryProvider.recheckRegistration(client);
      case NotificationDeliveryMode.backgroundService:
        break;
    }
  } catch (e) {
    debugPrint('zuno/push: recheck of ${mode.name} delivery failed: $e');
  }
}

Future<void> kickOffDeliveryMode(
  Client client,
  NotificationDeliveryMode mode,
) async {
  try {
    switch (mode) {
      case NotificationDeliveryMode.unifiedPush:
        await unifiedPushDeliveryProvider.discoverDistributorsIfNeeded();
      case NotificationDeliveryMode.fcm:
        await fcmDeliveryProvider.registerNow(client);
      case NotificationDeliveryMode.backgroundService:
        break;
    }
  } catch (e) {
    debugPrint('zuno/push: could not start ${mode.name} delivery: $e');
  }
}
