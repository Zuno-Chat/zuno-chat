import 'dart:async';

import 'package:matrix/matrix.dart';

import '../../calls/notifications/server_ring.dart';
import '../../errors/caught_errors.dart';
import '../apns/apns_delivery_provider.dart';
import '../background_sync/background_sync_delivery_provider.dart';
import '../fcm/fcm_delivery_provider.dart';
import '../fcm/fcm_startup.dart';
import '../handling/push_wake_lock.dart';
import '../pushers/push_gateway.dart';
import '../ring/ring_registration.dart';
import '../unified_push/unified_push_delivery_provider.dart';
import 'notification_delivery_mode.dart';
import 'notification_delivery_provider.dart';
import 'pusher_failure.dart';

final _backgroundSync = BackgroundSyncDeliveryProvider();

String? currentPushkeyFor(NotificationDeliveryMode mode) {
  return switch (mode) {
    NotificationDeliveryMode.unifiedPush =>
      unifiedPushDeliveryProvider.endpointUrl?.toString(),
    NotificationDeliveryMode.fcm => fcmDeliveryProvider.token,
    NotificationDeliveryMode.apns => apnsDeliveryProvider.pushkey,
    NotificationDeliveryMode.backgroundService => null,
  };
}

PusherFailure? lastPusherErrorFor(NotificationDeliveryMode mode) {
  return switch (mode) {
    NotificationDeliveryMode.unifiedPush =>
      unifiedPushDeliveryProvider.lastPusherError,
    NotificationDeliveryMode.fcm => fcmDeliveryProvider.lastPusherError,
    NotificationDeliveryMode.apns => apnsDeliveryProvider.lastPusherError,
    NotificationDeliveryMode.backgroundService => null,
  };
}

Uri? gatewayUrlFor(NotificationDeliveryMode mode, Client client) {
  return switch (mode) {
    NotificationDeliveryMode.unifiedPush =>
      unifiedPushDeliveryProvider.gatewayUrl,
    NotificationDeliveryMode.fcm || NotificationDeliveryMode.apns =>
      homeserverPushGatewayUri(client.homeserver),
    NotificationDeliveryMode.backgroundService => null,
  };
}

void bindAppStateToPushDelivery({
  required String? Function() currentlyOpenRoomId,
  required bool Function() isAppSyncing,
  required void Function(ServerRing ring) ringInApp,
}) {
  for (final runner in [
    fcmDeliveryProvider.runner,
    unifiedPushDeliveryProvider.runner,
  ]) {
    runner
      ..currentlyOpenRoomId = currentlyOpenRoomId
      ..isAppSyncing = isAppSyncing
      ..ringInApp = ringInApp
      ..nativeAppInFront = nativePushAppInFront;
  }
  unawaited(markFcmAppReady());
}

Future<void> stopAllNotificationDelivery(Client client) async {
  for (final mode in NotificationDeliveryMode.values) {
    try {
      await notificationDeliveryProviderFor(mode).stop(client);
    } catch (e, s) {
      reportCaught('delivery stop ${mode.name}', e, s);
    }
  }
  try {
    await ringRegistration.stop(client);
  } catch (e, s) {
    reportCaught('ring registration stop', e, s);
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
  } catch (e, s) {
    reportCaught('delivery retry ${mode.name}', e, s);
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
  } catch (e, s) {
    reportCaught('delivery recheck ${mode.name}', e, s);
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
  } catch (e, s) {
    reportCaught('delivery start ${mode.name}', e, s);
  }
}
