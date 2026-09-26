import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/security/user_trust.dart';

import '../../helpers/fake_device_keys.dart';
import '../../helpers/fake_encryption.dart';

UserTrustState _state({
  String? currentIdentityKey = 'KEY_A',
  bool identityDirectlyVerified = false,
  bool hasUnsignedDevices = false,
  String? confirmedIdentityKey,
}) => userTrustState(
  currentIdentityKey: currentIdentityKey,
  identityDirectlyVerified: identityDirectlyVerified,
  hasUnsignedDevices: hasUnsignedDevices,
  confirmedIdentityKey: confirmedIdentityKey,
);

void main() {
  group('userTrustState', () {
    test('someone with no identity has nothing to confirm', () {
      expect(_state(currentIdentityKey: null), UserTrustState.noIdentity);
    });

    test('an unconfirmed identity is the ordinary default', () {
      expect(_state(), UserTrustState.unconfirmed);
    });

    test('a confirmed identity with everything signed is confirmed', () {
      expect(
        _state(identityDirectlyVerified: true, confirmedIdentityKey: 'KEY_A'),
        UserTrustState.confirmed,
      );
    });

    test('a confirmed person with an unsigned device stays confirmed', () {
      expect(
        _state(
          identityDirectlyVerified: true,
          hasUnsignedDevices: true,
          confirmedIdentityKey: 'KEY_A',
        ),
        UserTrustState.confirmedWithPendingDevice,
      );
    });

    test('a replaced identity is identityChanged, not unconfirmed', () {
      expect(
        _state(confirmedIdentityKey: 'KEY_OLD'),
        UserTrustState.identityChanged,
      );
    });

    test('a replaced identity outranks it having been re-verified', () {
      expect(
        _state(identityDirectlyVerified: true, confirmedIdentityKey: 'KEY_OLD'),
        UserTrustState.identityChanged,
      );
    });

    test('losing the stored identity under-warns rather than crying wolf', () {
      expect(_state(confirmedIdentityKey: null), UserTrustState.unconfirmed);
    });
  });

  group('userTrustNeedsAttention', () {
    test('only a changed identity interrupts', () {
      for (final state in UserTrustState.values) {
        expect(
          userTrustNeedsAttention(state),
          state == UserTrustState.identityChanged,
          reason: state.name,
        );
      }
    });
  });

  group('userTrustFactsOf', () {
    const alice = '@alice:example.org';
    late EncryptedTestClient client;

    setUp(() => client = EncryptedTestClient(userId: '@me:example.org'));

    test('someone whose keys are unknown has no identity to go on', () {
      final facts = userTrustFactsOf(null);

      expect(facts.currentIdentityKey, isNull);
      expect(facts.identityDirectlyVerified, isFalse);
      expect(facts.hasUnsignedDevices, isFalse);
    });

    test('reads the identity and flags a device it has not signed', () {
      final list = setTestDevices(client, alice, {'A1': null});
      final master = testMasterKey(client, alice);

      final facts = userTrustFactsOf(list);

      expect(facts.currentIdentityKey, master.ed25519Key);
      expect(facts.identityDirectlyVerified, isFalse);
      expect(facts.hasUnsignedDevices, isTrue);
    });

    test('an identity I confirmed reads as directly verified', () async {
      final list = setTestDevices(client, alice, {});
      await testMasterKey(client, alice).setVerified(true, false);

      final facts = userTrustFactsOf(list);

      expect(facts.identityDirectlyVerified, isTrue);
      expect(facts.hasUnsignedDevices, isFalse);
    });
  });
}
