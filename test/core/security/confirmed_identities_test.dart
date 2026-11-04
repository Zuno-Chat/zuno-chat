import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/matrix/client/matrix_client_provider.dart';
import 'package:zuno/core/security/confirmed_identities.dart';
import 'package:zuno/core/security/confirmed_identity_store.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

import '../../helpers/fake_device_keys.dart';
import '../../helpers/fake_matrix.dart';

const _me = '@me:example.org';
const _bob = '@bob:example.org';

void main() {
  late SharedPreferences prefs;
  late ConfirmedIdentityStore store;
  late Client client;
  late CrossSigningKey bobs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = ConfirmedIdentityStore(prefs);
    client = buildTestClient(userId: _me, encrypting: true);
    testTrustedOwnIdentity(client);
    bobs = testMasterKey(client, _bob);
  });

  group('rememberConfirmedIdentity', () {
    final now = DateTime(2026, 11, 3, 9, 30);

    Future<void> remember() => withClock(
      Clock.fixed(now),
      () => rememberConfirmedIdentity(store, client.userDeviceKeys[_bob]!),
    );

    test('an identity confirmed on this device is remembered with the day '
        'it happened', () async {
      bobs.setDirectVerified(true);
      await remember();
      expect(store.confirmedIdentityKey(_bob), bobs.ed25519Key);
      expect(store.confirmedAt(_bob), now);
    });

    test('an identity confirmed on another device is remembered without a '
        'date, since this device never saw when', () async {
      testConfirmByMyAccount(bobs);
      await remember();
      expect(store.confirmedIdentityKey(_bob), bobs.ed25519Key);
      expect(store.confirmedAt(_bob), isNull);
    });

    test('an identity nobody confirmed is not remembered', () async {
      await remember();
      expect(store.confirmedIdentityKey(_bob), isNull);
    });

    test('an identity already remembered keeps its date', () async {
      final earlier = DateTime(2026, 10, 1);
      await store.remember(_bob, bobs.ed25519Key!, at: earlier);
      bobs.setDirectVerified(true);
      await remember();
      expect(store.confirmedAt(_bob), earlier);
    });

    test('an identity remembered without a date gets one once it is checked '
        'here', () async {
      await store.remember(_bob, bobs.ed25519Key!);
      bobs.setDirectVerified(true);
      await remember();
      expect(store.confirmedAt(_bob), now);
    });

    test(
      'a new identity your account confirmed replaces the old one',
      () async {
        await store.remember(_bob, 'KEY_OLD', at: DateTime(2026, 10, 1));
        testConfirmByMyAccount(bobs);
        await remember();
        expect(store.confirmedIdentityKey(_bob), bobs.ed25519Key);
      },
    );

    test('a new identity nobody confirmed leaves the old one, so the change '
        'still shows', () async {
      await store.remember(_bob, 'KEY_OLD');
      await remember();
      expect(store.confirmedIdentityKey(_bob), 'KEY_OLD');
    });
  });

  group('confirmedIdentityTrackerProvider', () {
    Future<void> watching() async {
      final container = ProviderContainer(
        overrides: [
          matrixClientProvider.overrideWithValue(client),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);
      container.listen(confirmedIdentityTrackerProvider, (_, _) {});
      await pumpEventQueue();
    }

    test('remembers who your account confirmed as soon as it starts', () async {
      testConfirmByMyAccount(bobs);
      await watching();
      expect(store.confirmedIdentityKey(_bob), bobs.ed25519Key);
    });

    test('each finished sync remembers a confirmation made since, but never '
        'your own identity', () async {
      await watching();
      testConfirmByMyAccount(bobs);

      client.onSyncStatus.add(SyncStatusUpdate(SyncStatus.finished));
      await pumpEventQueue();

      expect(store.confirmedIdentityKey(_bob), bobs.ed25519Key);
      expect(store.confirmedIdentityKey(_me), isNull);
    });
  });
}
