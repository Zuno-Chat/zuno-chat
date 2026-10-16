import 'package:matrix/matrix.dart';

abstract class NotificationDeliveryProvider {
  Future<void> start(Client client);

  Future<void> stop(Client client);
}
