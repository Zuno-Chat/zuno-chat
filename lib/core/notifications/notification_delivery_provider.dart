import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:matrix/matrix.dart';

import '../platform/platform_capabilities.dart';
import '../push/fcm_gateway.dart';
import '../push/fcm_startup.dart';
import '../push/push_wake_lock.dart';
import '../push/voip/voip_registration.dart';
import 'apns_delivery_provider.dart';
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

String? currentPushkeyFor(NotificationDeliveryMode mode) {
  switch (mode) {
    case NotificationDeliveryMode.unifiedPush:
      return unifiedPushDeliveryProvider.endpointUrl?.toString();
    case NotificationDeliveryMode.fcm:
      return fcmDeliveryProvider.token;
    case NotificationDeliveryMode.apns:
      return apnsDeliveryProvider.pushkey;
    case NotificationDeliveryMode.backgroundService:
      return null;
  }
}

String? lastPusherErrorFor(NotificationDeliveryMode mode) {
  switch (mode) {
    case NotificationDeliveryMode.unifiedPush:
      return unifiedPushDeliveryProvider.lastPusherError;
    case NotificationDeliveryMode.fcm:
      return fcmDeliveryProvider.lastPusherError;
    case NotificationDeliveryMode.apns:
      return apnsDeliveryProvider.lastPusherError;
    case NotificationDeliveryMode.backgroundService:
      return null;
  }
}

Uri? gatewayUrlFor(NotificationDeliveryMode mode, Client client) {
  switch (mode) {
    case NotificationDeliveryMode.unifiedPush:
      return unifiedPushDeliveryProvider.gatewayUrl;
    case NotificationDeliveryMode.fcm:
    case NotificationDeliveryMode.apns:
      return fcmGatewayUri(client.homeserver);
    case NotificationDeliveryMode.backgroundService:
      return null;
  }
}

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
      ..isAppSyncing = isAppSyncing
      ..nativeAppInFront = nativePushAppInFront;
  }
  unawaited(markFcmAppReady());
}

Future<void> stopAllNotificationDelivery(Client client) async {
  for (final mode in NotificationDeliveryMode.values) {
    try {
      await notificationDeliveryProviderFor(mode).stop(client);
    } catch (_) {}
  }
  if (ambientCapabilities.voipRing) {
    try {
      await voipRegistration.stop(client);
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
    NotificationDeliveryMode.apns => apnsDeliveryProvider,
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
      case NotificationDeliveryMode.apns:
        await apnsDeliveryProvider.retryIfFailed(client);
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
      case NotificationDeliveryMode.apns:
        await apnsDeliveryProvider.recheckRegistration(client);
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
      case NotificationDeliveryMode.apns:
        await apnsDeliveryProvider.registerNow(client);
      case NotificationDeliveryMode.backgroundService:
        break;
    }
  } catch (e) {
    debugPrint('zuno/push: could not start ${mode.name} delivery: $e');
  }
}
