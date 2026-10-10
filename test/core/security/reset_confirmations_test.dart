import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/security/confirmed_identity_store.dart';
import 'package:zuno/core/security/reset_confirmations.dart';

import '../../helpers/fake_device_keys.dart';
import '../../helpers/fake_encryption.dart';
import '../../helpers/fake_matrix.dart';

class _BrokenStore extends ConfirmedIdentityStore {
  _BrokenStore(super.prefs);

  @override
  Future<void> forgetAll() async => throw StateError('disk full');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('every confirmation this account made is forgotten', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = ConfirmedIdentityStore(prefs);
    await store.remember('@alex:example.org', 'MASTERKEYALEX');
    await store.remember('@bob:example.org', 'MASTERKEYBOB');
    expect(store.confirmedIdentityKey('@alex:example.org'), 'MASTERKEYALEX');

    await forgetConfirmationsAfterIdentityReset(
      buildTestClient(userId: '@me:example.org'),
      store,
    );

    expect(store.confirmedIdentityKey('@alex:example.org'), isNull);
    expect(store.confirmedIdentityKey('@bob:example.org'), isNull);
    expect(store.confirmedAt('@alex:example.org'), isNull);
  });

  test('a client with no user ID clears the store without throwing', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = ConfirmedIdentityStore(prefs);
    await store.remember('@alex:example.org', 'MASTERKEYALEX');

    await expectLater(
      forgetConfirmationsAfterIdentityReset(buildTestClient(), store),
      completes,
    );
    expect(store.confirmedIdentityKey('@alex:example.org'), isNull);
  });

  group('keys confirmed with the old identity', () {
    const me = '@me:example.org';
    const alice = '@alice:example.org';
    const bob = '@bob:example.org';
    const carol = '@carol:example.org';
    late EncryptedTestClient client;

    setUp(() => client = EncryptedTestClient(userId: me));

    Future<void> confirm(String userId) =>
        testMasterKey(client, userId).setVerified(true, false);

    bool confirmed(String userId) =>
        client.userDeviceKeys[userId]!.masterKey!.directVerified;

    test('are no longer marked confirmed, my own identity aside', () async {
      await confirm(me);
      await confirm(alice);
      testMasterKey(client, bob);
      client.encryptionDatabase.verifiedCrossSigningKeys.clear();
      final prefs = await SharedPreferences.getInstance();

      await forgetConfirmationsAfterIdentityReset(
        client,
        ConfirmedIdentityStore(prefs),
      );

      expect(confirmed(alice), isFalse);
      expect(confirmed(me), isTrue);
      expect(client.encryptionDatabase.verifiedCrossSigningKeys, {
        alice: false,
      });
    });

    test('one key that cannot be updated does not stop the rest', () async {
      await confirm(alice);
      await confirm(carol);
      client.encryptionDatabase
        ..verifiedCrossSigningKeys.clear()
        ..refusingUsers.add(alice);
      final prefs = await SharedPreferences.getInstance();

      await forgetConfirmationsAfterIdentityReset(
        client,
        ConfirmedIdentityStore(prefs),
      );

      expect(client.encryptionDatabase.verifiedCrossSigningKeys, {
        carol: false,
      });
    });

    test('a device list that changes mid-reset does not stop it', () async {
      const dave = '@dave:example.org';
      await confirm(alice);
      await confirm(carol);
      client.encryptionDatabase
        ..verifiedCrossSigningKeys.clear()
        ..onStore = (_) => client.userDeviceKeys.putIfAbsent(
          dave,
          () => DeviceKeysList(dave, client),
        );
      final prefs = await SharedPreferences.getInstance();

      await forgetConfirmationsAfterIdentityReset(
        client,
        ConfirmedIdentityStore(prefs),
      );

      expect(confirmed(alice), isFalse);
      expect(confirmed(carol), isFalse);
    });

    test('a store that cannot be cleared still un-confirms people', () async {
      await confirm(alice);
      final prefs = await SharedPreferences.getInstance();

      await forgetConfirmationsAfterIdentityReset(client, _BrokenStore(prefs));

      expect(confirmed(alice), isFalse);
    });
  });
}
