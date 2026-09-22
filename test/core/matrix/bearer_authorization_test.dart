import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/bearer_authorization.dart';

import '../../helpers/fake_matrix.dart';

class _ExpiringClient extends Client {
  _ExpiringClient(this.expiresAt)
    : super(
        'test',
        database: FakeDatabaseApi(),
        onSoftLogout: (client) async => client.accessToken = 'fresh',
      );

  final DateTime expiresAt;

  @override
  DateTime? get accessTokenExpiresAt => expiresAt;
}

void main() {
  test('a token about to expire is refreshed before it is sent', () async {
    final client = _ExpiringClient(
      DateTime.now().add(const Duration(seconds: 30)),
    )..accessToken = 'stale';

    expect(await bearerAuthorization(client), 'Bearer fresh');
  });

  test('a token with time left is sent as is', () async {
    final client = _ExpiringClient(DateTime.now().add(const Duration(hours: 1)))
      ..accessToken = 'current';

    expect(await bearerAuthorization(client), 'Bearer current');
  });

  test('throws rather than sending an empty bearer when logged out', () async {
    await expectLater(bearerAuthorization(buildTestClient()), throwsStateError);
  });
}
