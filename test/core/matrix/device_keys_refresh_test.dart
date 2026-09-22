import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/device_keys_refresh.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  test('forces the next /keys/query after signing a device out', () {
    final client = buildTestClient(userId: '@alice:example.org');
    final list = DeviceKeysList('@alice:example.org', client)..outdated = false;
    client.userDeviceKeys['@alice:example.org'] = list;

    markOwnDeviceKeysOutdated(client);

    expect(list.outdated, isTrue);
  });

  test('leaves other users\' device lists alone', () {
    final client = buildTestClient(userId: '@alice:example.org');
    client.userDeviceKeys['@alice:example.org'] = DeviceKeysList(
      '@alice:example.org',
      client,
    )..outdated = false;
    final other = DeviceKeysList('@bob:example.org', client)..outdated = false;
    client.userDeviceKeys['@bob:example.org'] = other;

    markOwnDeviceKeysOutdated(client);

    expect(other.outdated, isFalse);
  });

  test('does nothing once signed out', () {
    final client = buildTestClient();

    expect(() => markOwnDeviceKeysOutdated(client), returnsNormally);
  });

  test('does nothing for an account whose keys were never queried', () {
    final client = buildTestClient(userId: '@alice:example.org');

    expect(() => markOwnDeviceKeysOutdated(client), returnsNormally);
    expect(client.userDeviceKeys, isEmpty);
  });
}
