import 'dart:async';

import 'package:matrix/encryption.dart';
import 'package:matrix/encryption/utils/ssss_cache.dart';
import 'package:matrix/matrix.dart';

import 'fake_matrix.dart';

class EncryptionDatabase extends FakeDatabaseApi {
  final secretCacheReads = <String>[];
  final heldSecretCacheReads = <String, Completer<Null>>{};
  final verifiedCrossSigningKeys = <String, bool>{};
  final verifiedDevices = <String, bool>{};
  final refusingUsers = <String>{};
  final cachedSecrets = <String>{};

  @override
  Future<SSSSCache?> getSSSSCache(String type) {
    secretCacheReads.add(type);
    final held = heldSecretCacheReads[type]?.future;
    if (held != null) return held;
    return Future.value(
      cachedSecrets.contains(type)
          ? SSSSCache(
              type: type,
              keyId: 'KEY',
              ciphertext: 'ciphertext',
              content: 'secret',
            )
          : null,
    );
  }

  @override
  Future<void> setVerifiedUserCrossSigningKey(
    bool verified,
    String userId,
    String publicKey, {
    DateTime? trustOnFirstUseSince,
  }) async {
    if (refusingUsers.contains(userId)) throw StateError('database locked');
    verifiedCrossSigningKeys[userId] = verified;
  }

  @override
  Future<void> setVerifiedUserDeviceKey(
    bool verified,
    String userId,
    String deviceId,
  ) async => verifiedDevices['$userId/$deviceId'] = verified;
}

class EncryptedTestClient extends Client {
  EncryptedTestClient({String? userId, this.testDeviceId, super.httpClient})
    : super('test', database: EncryptionDatabase()) {
    if (userId != null) setUserId(userId);
  }

  final String? testDeviceId;

  late final Encryption realEncryption = Encryption(client: this);

  EncryptionDatabase get encryptionDatabase => database as EncryptionDatabase;

  @override
  Encryption? get encryption => realEncryption;

  @override
  String? get deviceID => testDeviceId;

  void storeSecretOnServer(String type) => accountData[type] = BasicEvent(
    type: type,
    content: {
      'encrypted': {
        'KEY': {'iv': 'iv', 'ciphertext': 'ciphertext', 'mac': 'mac'},
      },
    },
  );

  void setUpRecovery({bool withKeyBackup = true}) {
    for (final type in [
      EventTypes.CrossSigningMasterKey,
      EventTypes.CrossSigningSelfSigning,
      EventTypes.CrossSigningUserSigning,
      if (withKeyBackup) EventTypes.MegolmBackup,
    ]) {
      storeSecretOnServer(type);
    }
  }

  void unlockRecovery() => encryptionDatabase.cachedSecrets.addAll([
    EventTypes.CrossSigningSelfSigning,
    EventTypes.CrossSigningUserSigning,
    EventTypes.MegolmBackup,
  ]);
}
