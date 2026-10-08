import 'package:matrix/matrix.dart';

import '../location/live_location_sharing.dart';
import '../notifications/notification_delivery_provider.dart';

const _liveShareStopBound = Duration(seconds: 5);

Future<void> signOutThisDevice(
  Client client, {
  required LiveLocationSharing liveLocation,
  Future<void> Function(Client client) stopDelivery =
      stopAllNotificationDelivery,
}) async {
  await liveLocation.stopAll(within: _liveShareStopBound);
  await stopDelivery(client);
  await client.logout();
}
