import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unifiedpush_platform_interface/unifiedpush_platform_interface.dart';
import 'package:zuno/core/notifications/delivery_failure.dart';
import 'package:zuno/core/notifications/delivery_failure_provider.dart';
import 'package:zuno/core/notifications/fcm_delivery_provider.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/notifications/notification_permission_provider.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

import '../../helpers/app_lifecycle.dart';
import '../../helpers/fake_unified_push.dart';
import '../../helpers/platform_capabilities.dart';

class _FixedNotificationsAllowed extends NotificationsAllowedNotifier {
  _FixedNotificationsAllowed(this._allowed);
  final bool? _allowed;

  @override
  bool? build() => _allowed;
}

class _Distributors extends FakeUnifiedPush {
  List<String> installed = const [];
  int lookups = 0;

  @override
  Future<List<String>> getDistributors(List<String> features) async {
    lookups++;
    return installed;
  }
}

Future<ProviderContainer> _container({
  required bool? allowed,
  String mode = 'backgroundService',
  String? autoSelected = 'backgroundService',
  PlatformCapabilities? capabilities,
}) async {
  SharedPreferences.setMockInitialValues({
    'settings.notification_delivery_mode': mode,
    notificationDeliveryModeAutoKey: ?autoSelected,
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      notificationsAllowedProvider.overrideWith(
        () => _FixedNotificationsAllowed(allowed),
      ),
      if (capabilities != null)
        platformCapabilitiesProvider.overrideWithValue(capabilities),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

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

  group('without Google Play services', () {
    late _Distributors distributors;

    setUp(() {
      distributors = _Distributors();
      final original = UnifiedPushPlatform.instance;
      UnifiedPushPlatform.instance = distributors;
      fcmDeliveryProvider.status.value = FcmStatus.playServicesUnavailable;
      addTearDown(() {
        UnifiedPushPlatform.instance = original;
        fcmDeliveryProvider.status.value = FcmStatus.idle;
      });
    });

    Future<DeliveryFailureAction?> actionOffered(
      ProviderContainer container,
    ) async {
      container.listen(deliveryFailureProvider, (_, _) {});
      await container.read(unifiedPushDistributorInstalledProvider.future);
      return container.read(deliveryFailureProvider)?.action;
    }

    test('offers background sync when no distributor is installed', () async {
      final container = await _container(
        allowed: true,
        mode: 'fcm',
        autoSelected: null,
      );

      expect(
        await actionOffered(container),
        DeliveryFailureAction.switchToBackgroundService,
      );
    });

    test('offers UnifiedPush when a distributor is installed', () async {
      distributors.installed = ['io.heckel.ntfy'];
      final container = await _container(
        allowed: true,
        mode: 'fcm',
        autoSelected: null,
      );

      expect(
        await actionOffered(container),
        DeliveryFailureAction.switchToUnifiedPush,
      );
    });

    test('looks again when Zuno comes back to the front', () async {
      final container = await _container(
        allowed: true,
        mode: 'fcm',
        autoSelected: null,
      );
      expect(
        await actionOffered(container),
        DeliveryFailureAction.switchToBackgroundService,
      );

      distributors.installed = ['io.heckel.ntfy'];
      moveLifecycleTo(binding, AppLifecycleState.paused);
      moveLifecycleTo(binding, AppLifecycleState.resumed);

      expect(
        await actionOffered(container),
        DeliveryFailureAction.switchToUnifiedPush,
      );
    });

    test('a distributor list that cannot be read offers background '
        'sync', () async {
      UnifiedPushPlatform.instance = DefaultUnifiedPush();
      final container = await _container(
        allowed: true,
        mode: 'fcm',
        autoSelected: null,
      );

      expect(
        await actionOffered(container),
        DeliveryFailureAction.switchToBackgroundService,
      );
    });

    test('never lists distributors where UnifiedPush is not offered', () async {
      final container = await _container(
        allowed: true,
        mode: 'fcm',
        autoSelected: null,
        capabilities: capabilitiesLike(
          androidCapabilities,
          deliveryModes: const [
            NotificationDeliveryMode.fcm,
            NotificationDeliveryMode.backgroundService,
          ],
        ),
      );

      expect(
        await actionOffered(container),
        DeliveryFailureAction.switchToBackgroundService,
      );
      expect(distributors.lookups, 0);
    });

    test('never lists distributors while another method is in use', () async {
      final container = await _container(allowed: true, autoSelected: null);

      container.listen(deliveryFailureProvider, (_, _) {});
      await pumpEventQueue();

      expect(
        container.exists(unifiedPushDistributorInstalledProvider),
        isFalse,
      );
      expect(distributors.lookups, 0);
    });
  });
}
