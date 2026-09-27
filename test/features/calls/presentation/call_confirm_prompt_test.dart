import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/security/user_trust.dart';
import 'package:zuno/features/calls/presentation/call_confirm_prompt.dart';

void main() {
  bool wanted({
    UserTrustState trust = UserTrustState.unconfirmed,
    bool deviceReady = true,
    bool declined = false,
    bool talkedLongEnough = true,
  }) => callConfirmPromptWanted(
    trust: trust,
    deviceReady: deviceReady,
    declined: declined,
    talkedLongEnough: talkedLongEnough,
  );

  test('offered for someone not yet confirmed, once the call has settled', () {
    expect(wanted(), isTrue);
  });

  test('offered again for someone whose details changed', () {
    expect(wanted(trust: UserTrustState.identityChanged), isTrue);
  });

  test('never for someone confirmed or who cannot be confirmed', () {
    for (final trust in [
      UserTrustState.confirmed,
      UserTrustState.confirmedWithPendingDevice,
      UserTrustState.noIdentity,
    ]) {
      expect(wanted(trust: trust), isFalse, reason: trust.name);
    }
  });

  test('not in the first half minute', () {
    expect(wanted(talkedLongEnough: false), isFalse);
  });

  test('not while this device cannot confirm anyone', () {
    expect(wanted(deviceReady: false), isFalse);
  });

  test('not after Not now for that person', () {
    expect(wanted(declined: true), isFalse);
  });
}
