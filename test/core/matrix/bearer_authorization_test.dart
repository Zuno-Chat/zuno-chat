import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/bearer_authorization.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  test('a token about to expire is refreshed before it is sent', () async {
    final client = ExpiringTokenClient()..accessToken = 'stale';

    expect(await bearerAuthorization(client), 'Bearer fresh');
  });

  test('a token with time left is sent as is', () async {
    final client = ExpiringTokenClient(expiresIn: const Duration(hours: 1))
      ..accessToken = 'current';

    expect(await bearerAuthorization(client), 'Bearer current');
  });

  test('throws rather than sending an empty bearer when logged out', () async {
    await expectLater(bearerAuthorization(buildTestClient()), throwsStateError);
  });
}
