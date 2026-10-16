import 'package:matrix/encryption.dart';
import 'package:matrix/encryption/utils/olm_session.dart';
import 'package:matrix/matrix.dart';

Map<String, Object?> testDeviceKeysJson(
  String userId,
  String deviceId, {
  String? name,
}) => {
  'user_id': userId,
  'device_id': deviceId,
  'algorithms': <String>[],
  'keys': {
    'curve25519:$deviceId': 'curve-$deviceId',
    'ed25519:$deviceId': 'ed-$deviceId',
  },
  'signatures': <String, Object?>{},
  if (name != null) 'unsigned': {'device_display_name': name},
};

DeviceKeys testDeviceKeys(
  Client client,
  String userId,
  String deviceId, {
  String? name,
}) => DeviceKeys.fromJson(
  testDeviceKeysJson(userId, deviceId, name: name),
  client,
);

void openTestOlmSession(Encryption encryption, String deviceId) =>
    encryption.olmManager.olmSessions['curve-$deviceId'] = [
      OlmSession(
        key: 'pickle-key',
        identityKey: 'curve-$deviceId',
        sessionId: 'olm-$deviceId',
        session: null,
        lastReceived: null,
      ),
    ];

class SelfSignedTestDeviceKeys extends DeviceKeys {
  SelfSignedTestDeviceKeys(super.json, super.client) : super.fromJson();

  @override
  bool get selfSigned => true;
}

class ApprovedTestDeviceKeys extends DeviceKeys {
  ApprovedTestDeviceKeys(super.json, super.client) : super.fromJson();

  @override
  bool get verified => true;
}

class OwnerSignedTestDeviceKeys extends DeviceKeys {
  OwnerSignedTestDeviceKeys(super.json, super.client) : super.fromJson();

  @override
  bool hasValidSignatureChain({
    bool verifiedOnly = true,
    Set<String>? visited,
    Set<String>? onlyValidateUserIds,
    bool verifiedByTheirMasterKey = false,
  }) => verifiedByTheirMasterKey;
}

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

DeviceKeysList setSelfSignedTestDevices(
  Client client,
  String userId,
  List<String> deviceIds,
) => _keysOf(client, userId)
  ..outdated = false
  ..deviceKeys = {
    for (final id in deviceIds)
      id: SelfSignedTestDeviceKeys(testDeviceKeysJson(userId, id), client),
  };

CrossSigningKey testMasterKey(
  Client client,
  String userId, {
  String? publicKey,
}) {
  publicKey ??= 'master-$userId';
  final key = CrossSigningKey.fromJson({
    'user_id': userId,
    'usage': ['master'],
    'keys': {'ed25519:$publicKey': publicKey},
    'signatures': <String, Object?>{},
  }, client);
  _keysOf(client, userId).crossSigningKeys
    ..removeWhere((_, existing) => existing.usage.contains('master'))
    ..[publicKey] = key;
  return key;
}
