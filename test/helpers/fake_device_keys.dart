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
}) => _crossSigningKey(client, userId, 'master', publicKey ?? 'master-$userId');

CrossSigningKey testTrustedOwnIdentity(Client client) =>
    testMasterKey(client, client.userID!)..setDirectVerified(true);

void testConfirmByMyAccount(CrossSigningKey identity) {
  final client = identity.client;
  final ownId = client.userID!;
  final userSigning = _crossSigningKey(
    client,
    ownId,
    'user_signing',
    'user-signing-$ownId',
  );
  testSign(userSigning, by: client.userDeviceKeys[ownId]!.masterKey!);
  testSign(identity, by: userSigning);
}

CrossSigningKey _crossSigningKey(
  Client client,
  String userId,
  String usage,
  String publicKey,
) {
  final key = CrossSigningKey.fromJson({
    'user_id': userId,
    'usage': [usage],
    'keys': {'ed25519:$publicKey': publicKey},
    'signatures': <String, Object?>{},
  }, client);
  _keysOf(client, userId).crossSigningKeys
    ..removeWhere((_, existing) => existing.usage.contains(usage))
    ..[publicKey] = key;
  return key;
}

void testSign(SignableKey key, {required SignableKey by}) {
  final keyId = 'ed25519:${by.identifier}';
  ((key.signatures ??= {})[by.userId] ??= {})[keyId] = 'signature';
  ((key.validSignatures ??= {})[by.userId] ??= <String, dynamic>{})[keyId] =
      true;
}
