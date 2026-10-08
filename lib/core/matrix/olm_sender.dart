import 'package:matrix/matrix.dart';

DeviceKeys? olmSenderDevice(Client client, ToDeviceEvent event) {
  final senderKey = event.encryptedContent?['sender_key'];
  if (senderKey is! String) return null;
  final device = client.userDeviceKeys[event.senderId]?.deviceKeys.values
      .where((device) => device.curve25519Key == senderKey)
      .firstOrNull;
  if (device == null || device.blocked || device.deviceId == null) return null;
  return device;
}
