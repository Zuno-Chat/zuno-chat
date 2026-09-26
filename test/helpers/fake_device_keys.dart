import 'package:matrix/matrix.dart';

DeviceKeys testDeviceKeys(
  Client client,
  String userId,
  String deviceId, {
  String? name,
}) => DeviceKeys.fromJson({
  'user_id': userId,
  'device_id': deviceId,
  'algorithms': <String>[],
  'keys': {
    'curve25519:$deviceId': 'curve-$deviceId',
    'ed25519:$deviceId': 'ed-$deviceId',
  },
  'signatures': <String, Object?>{},
  if (name != null) 'unsigned': {'device_display_name': name},
}, client);

DeviceKeysList _keysOf(Client client, String userId) =>
    client.userDeviceKeys[userId] ??= DeviceKeysList(userId, client);

DeviceKeysList setTestDevices(
  Client client,
  String userId,
  Map<String, String?> devices, {
  bool outdated = false,
}) => _keysOf(client, userId)
  ..outdated = outdated
  ..deviceKeys = {
    for (final MapEntry(key: id, value: name) in devices.entries)
      id: testDeviceKeys(client, userId, id, name: name),
  };

CrossSigningKey testMasterKey(Client client, String userId) {
  final publicKey = 'master-$userId';
  final key = CrossSigningKey.fromJson({
    'user_id': userId,
    'usage': ['master'],
    'keys': {'ed25519:$publicKey': publicKey},
    'signatures': <String, Object?>{},
  }, client);
  _keysOf(client, userId).crossSigningKeys[publicKey] = key;
  return key;
}
