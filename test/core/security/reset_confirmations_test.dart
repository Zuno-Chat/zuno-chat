import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/security/confirmed_identity_store.dart';
import 'package:zuno/core/security/reset_confirmations.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('every confirmation this account made is forgotten', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = ConfirmedIdentityStore(prefs);
    await store.remember('@alex:example.org', 'MASTERKEYALEX');
    await store.remember('@bob:example.org', 'MASTERKEYBOB');
    expect(store.confirmedIdentityKey('@alex:example.org'), isNotNull);

    await forgetConfirmationsAfterIdentityReset(
      buildTestClient(userId: '@me:example.org'),
      store,
    );

    expect(store.confirmedIdentityKey('@alex:example.org'), isNull);
    expect(store.confirmedIdentityKey('@bob:example.org'), isNull);
    expect(store.confirmedAt('@alex:example.org'), isNull);
  });

  test('an account with nothing confirmed is a no-op, not an error', () async {
    final prefs = await SharedPreferences.getInstance();

    await expectLater(
      forgetConfirmationsAfterIdentityReset(
        buildTestClient(userId: '@me:example.org'),
        ConfirmedIdentityStore(prefs),
      ),
      completes,
    );
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
}
