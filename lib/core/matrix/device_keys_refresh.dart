import 'package:matrix/matrix.dart';

void markOwnDeviceKeysOutdated(Client client) {
  final userId = client.userID;
  if (userId == null) return;
  client.userDeviceKeys[userId]?.outdated = true;
}
