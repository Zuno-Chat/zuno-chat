import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/notifications/notification_permission_provider.dart';

import '../../helpers/fake_permissions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePermissions permissions;

  setUp(() => permissions = installFakePermissions());

  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('starts null until the first real read lands', () {
    final c = container();
    expect(c.read(notificationsAllowedProvider), isNull);
  });

  test('resolves to false when permanently denied', () async {
    permissions.onCheck = permissionPermanentlyDenied;
    final c = container();
    await c.read(notificationsAllowedProvider.notifier).refresh();
    expect(c.read(notificationsAllowedProvider), isFalse);
  });

  test('picks up a revocation on a later refresh', () async {
    final c = container();
    await c.read(notificationsAllowedProvider.notifier).refresh();
    expect(c.read(notificationsAllowedProvider), isTrue);

    permissions.onCheck = permissionDenied;
    await c.read(notificationsAllowedProvider.notifier).refresh();
    expect(c.read(notificationsAllowedProvider), isFalse);
  });

  test('a channel failure leaves the last known value alone', () async {
    final c = container();
    await c.read(notificationsAllowedProvider.notifier).refresh();
    expect(c.read(notificationsAllowedProvider), isTrue);

    permissions.error = PlatformException(code: 'boom');
    await c.read(notificationsAllowedProvider.notifier).refresh();
    expect(c.read(notificationsAllowedProvider), isTrue);
  });
}
