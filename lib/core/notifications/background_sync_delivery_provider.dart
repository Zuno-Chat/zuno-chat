import 'package:matrix/matrix.dart';

import 'background_sync_service.dart';
import 'notification_delivery_provider.dart';
import 'notification_permission.dart';

class BackgroundSyncDeliveryProvider implements NotificationDeliveryProvider {
  Future<bool> Function() notificationsAllowed = mayRegisterForNotifications;

  @override
  Future<void> start(Client client) async {
    if (!await notificationsAllowed()) return;
    await BackgroundSyncService.instance.start();
  }

  @override
  Future<void> stop(Client client) => BackgroundSyncService.instance.stop();
}
