import 'package:matrix/matrix.dart';

import '../../notifications/settings/notification_permission.dart';
import '../delivery/notification_delivery_provider.dart';
import 'background_sync_service.dart';

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
