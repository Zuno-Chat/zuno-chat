import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/notifications/notification_permission_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mockStatus(int status, {bool throwInstead = false}) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (throwInstead) throw PlatformException(code: 'boom');
      if (call.method == 'checkPermissionStatus') return status;
      return null;
    });
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('starts null until the first real read lands', () {
    mockStatus(1);
    final c = container();
    expect(c.read(notificationsAllowedProvider), isNull);
  });

  test('resolves to true when the permission is granted', () async {
    mockStatus(1);
    final c = container();
    await c.read(notificationsAllowedProvider.notifier).refresh();
    expect(c.read(notificationsAllowedProvider), isTrue);
  });

  test('resolves to false when denied', () async {
    mockStatus(0);
    final c = container();
    await c.read(notificationsAllowedProvider.notifier).refresh();
    expect(c.read(notificationsAllowedProvider), isFalse);
  });

  test('resolves to false when permanently denied', () async {
    mockStatus(4);
    final c = container();
    await c.read(notificationsAllowedProvider.notifier).refresh();
    expect(c.read(notificationsAllowedProvider), isFalse);
  });

  test('picks up a revocation on a later refresh', () async {
    mockStatus(1);
    final c = container();
    await c.read(notificationsAllowedProvider.notifier).refresh();
    expect(c.read(notificationsAllowedProvider), isTrue);

    mockStatus(0);
    await c.read(notificationsAllowedProvider.notifier).refresh();
    expect(c.read(notificationsAllowedProvider), isFalse);
  });

  test('a channel failure leaves the last known value alone', () async {
    mockStatus(1);
    final c = container();
    await c.read(notificationsAllowedProvider.notifier).refresh();
    expect(c.read(notificationsAllowedProvider), isTrue);

    mockStatus(0, throwInstead: true);
    await c.read(notificationsAllowedProvider.notifier).refresh();
    expect(c.read(notificationsAllowedProvider), isTrue);
  });
}
