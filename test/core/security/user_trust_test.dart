import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/security/user_trust.dart';

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
}
