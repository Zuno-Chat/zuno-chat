import 'package:matrix/matrix.dart';

import 'background_sync_service.dart';
import 'notification_delivery_provider.dart';

class BackgroundSyncDeliveryProvider implements NotificationDeliveryProvider {
  @override
  Future<void> start(Client client) => BackgroundSyncService.instance.start();

  @override
  Future<void> stop(Client client) => BackgroundSyncService.instance.stop();
}
