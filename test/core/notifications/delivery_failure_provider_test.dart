import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/notifications/delivery_failure_provider.dart';
import 'package:zuno/core/notifications/notification_permission_provider.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

class _FixedNotificationsAllowed extends NotificationsAllowedNotifier {
  _FixedNotificationsAllowed(this._allowed);
  final bool? _allowed;

  @override
  bool? build() => _allowed;
}

Future<ProviderContainer> _container({required bool? allowed}) async {
  SharedPreferences.setMockInitialValues({
    'settings.notification_delivery_mode': 'backgroundService',
    notificationDeliveryModeAutoKey: 'backgroundService',
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      notificationsAllowedProvider.overrideWith(
        () => _FixedNotificationsAllowed(allowed),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('shows the switched-method notice while notifications are on', () async {
    final container = await _container(allowed: true);

    expect(container.read(deliveryFailureProvider)?.notice, isTrue);
  });

  test('shows nothing about delivery while notifications are off', () async {
    final container = await _container(allowed: false);

    expect(container.read(deliveryFailureProvider), isNull);
  });

  test('shows nothing until the permission is known', () async {
    final container = await _container(allowed: null);

    expect(container.read(deliveryFailureProvider), isNull);
  });
}
