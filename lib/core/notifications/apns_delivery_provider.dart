import 'package:matrix/matrix.dart';

import 'notification_delivery_provider.dart';

class ApnsDeliveryProvider implements NotificationDeliveryProvider {
  @override
  Future<void> start(Client client) async {}

  @override
  Future<void> stop(Client client) async {}
}
