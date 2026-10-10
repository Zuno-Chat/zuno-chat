import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/notifications/fcm_availability_provider.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/fcm_bridge.dart';

import '../../helpers/app_lifecycle.dart';
import '../../helpers/platform_capabilities.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  group('fcmAvailabilityProvider', () {
    const channel = MethodChannel('zuno/fcm');
    late List<String> calls;
    late Object? Function() answer;

    setUp(() {
      calls = [];
      answer = () => 'available';
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        return answer();
      });
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
    });

    ProviderContainer containerOn(PlatformCapabilities capabilities) {
      final container = ProviderContainer(
        overrides: [
          platformCapabilitiesProvider.overrideWithValue(capabilities),
        ],
      );
      addTearDown(container.dispose);
      container.listen(fcmAvailabilityProvider, (_, _) {});
      return container;
    }

    test('reports what this device says', () async {
      answer = () => 'updateRequired';
      final container = containerOn(androidCapabilities);

      expect(
        await container.read(fcmAvailabilityProvider.future),
        FcmAvailability.updateRequired,
      );
      expect(calls, ['availability']);
    });

    test('a check that fails reads as unknown, not unavailable', () async {
      answer = () => throw PlatformException(code: 'boom');
      final container = containerOn(androidCapabilities);

      expect(
        await container.read(fcmAvailabilityProvider.future),
        FcmAvailability.unknown,
      );
    });

    test('never asks where Google services is not offered', () async {
      final container = containerOn(iosCapabilities);

      expect(
        await container.read(fcmAvailabilityProvider.future),
        FcmAvailability.unavailable,
      );
      moveLifecycleTo(binding, AppLifecycleState.paused);
      moveLifecycleTo(binding, AppLifecycleState.resumed);
      await container.read(fcmAvailabilityProvider.future);

      expect(calls, isEmpty);
    });

    test('asks again when Zuno comes back to the front', () async {
      answer = () => 'disabled';
      final container = containerOn(androidCapabilities);
      expect(
        await container.read(fcmAvailabilityProvider.future),
        FcmAvailability.disabled,
      );

      answer = () => 'available';
      moveLifecycleTo(binding, AppLifecycleState.paused);
      moveLifecycleTo(binding, AppLifecycleState.resumed);

      expect(
        await container.read(fcmAvailabilityProvider.future),
        FcmAvailability.available,
      );
      expect(calls, ['availability', 'availability']);
    });

    test('keeps the last answer on screen while it asks again', () async {
      answer = () => 'disabled';
      final container = containerOn(androidCapabilities);
      await container.read(fcmAvailabilityProvider.future);

      moveLifecycleTo(binding, AppLifecycleState.paused);
      moveLifecycleTo(binding, AppLifecycleState.resumed);

      expect(
        container.read(fcmAvailabilityProvider).value,
        FcmAvailability.disabled,
      );
    });
  });

  group('deliveryModeChoice', () {
    test('the other methods are always open, with their usual '
        'description', () {
      for (final mode in [
        NotificationDeliveryMode.unifiedPush,
        NotificationDeliveryMode.backgroundService,
        NotificationDeliveryMode.apns,
      ]) {
        for (final fcm in [null, ...FcmAvailability.values]) {
          expect(deliveryModeChoice(mode, fcm: fcm), (
            enabled: true,
            subtitle: mode.description,
          ), reason: '$mode/$fcm');
        }
      }
    });

    test('Google services is open on a device that can use it', () {
      expect(
        deliveryModeChoice(
          NotificationDeliveryMode.fcm,
          fcm: FcmAvailability.available,
        ),
        (enabled: true, subtitle: NotificationDeliveryMode.fcm.description),
      );
    });

    test('a device whose check failed can still pick it, since only a '
        'confirmed answer closes it', () {
      expect(
        deliveryModeChoice(
          NotificationDeliveryMode.fcm,
          fcm: FcmAvailability.unknown,
        ),
        (enabled: true, subtitle: NotificationDeliveryMode.fcm.description),
      );
    });

    test('a device that needs an update can still pick it, and is told '
        'what comes next', () {
      expect(
        deliveryModeChoice(
          NotificationDeliveryMode.fcm,
          fcm: FcmAvailability.updateRequired,
        ),
        (
          enabled: true,
          subtitle:
              'Google Play services needs an update. Zuno offers the update '
              'once you choose this.',
        ),
      );
    });

    for (final (fcm, reason) in [
      (
        FcmAvailability.unavailable,
        'This device does not have Google Play services.',
      ),
      (
        FcmAvailability.disabled,
        'Google Play services is turned off. Turn it on in your device '
            'settings to use this.',
      ),
      (
        FcmAvailability.notConfigured,
        'This version of Zuno does not include Google services.',
      ),
    ]) {
      test('${fcm.name} closes Google services and says why', () {
        expect(deliveryModeChoice(NotificationDeliveryMode.fcm, fcm: fcm), (
          enabled: false,
          subtitle: reason,
        ));
      });
    }

    test('Google services waits while this device is checked', () {
      expect(deliveryModeChoice(NotificationDeliveryMode.fcm, fcm: null), (
        enabled: false,
        subtitle: 'Checking this device…',
      ));
    });
  });
}
