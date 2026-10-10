import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unifiedpush_platform_interface/unifiedpush_platform_interface.dart';
import 'package:zuno/core/notifications/apns_delivery_provider.dart';
import 'package:zuno/core/notifications/delivery_failure.dart';
import 'package:zuno/core/notifications/delivery_failure_provider.dart';
import 'package:zuno/core/notifications/fcm_delivery_provider.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/notifications/notification_delivery_provider.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/voip/voip_registration.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

import '../../helpers/app_lifecycle.dart';
import '../../helpers/fake_unified_push.dart';
import '../../helpers/fake_voip_registration.dart';
import '../../helpers/fixed_notifications_allowed.dart';
import '../../helpers/platform_capabilities.dart';
import '../../helpers/preferences_container.dart';

Future<ProviderContainer> _container({
  required bool? allowed,
  String mode = 'backgroundService',
  String? autoSelected = 'backgroundService',
  PlatformCapabilities? capabilities,
  VoipRegistration? voip,
}) => containerWithPreferences(
  {
    'settings.notification_delivery_mode': mode,
    notificationDeliveryModeAutoKey: ?autoSelected,
  },
  overrides: [
    fixedNotificationsAllowed(allowed),
    if (capabilities != null)
      platformCapabilitiesProvider.overrideWithValue(capabilities),
    if (voip != null) voipRegistrationProvider.overrideWithValue(voip),
  ],
);

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

  group('calls on iOS', () {
    late FakeVoipRegistration voip;

    setUp(() => voip = FakeVoipRegistration());

    Future<ProviderContainer> start({required bool? allowed}) => _container(
      allowed: allowed,
      mode: 'apns',
      autoSelected: null,
      capabilities: capabilitiesLike(iosCapabilities, voipRing: true),
      voip: voip,
    );

    test('a refused call registration shows the calls failure, even with '
        'notifications off', () async {
      final container = await start(allowed: false);

      voip.stateValue.value = VoipRegistrationState.failed;

      expect(container.read(deliveryFailureProvider), callsSetupFailed);
    });

    test('a server that is not there yet stays quiet', () async {
      final container = await start(allowed: true);

      voip.stateValue.value = VoipRegistrationState.unreachable;

      expect(container.read(deliveryFailureProvider), isNull);
    });

    test(
      'a failing alert registration is shown before the calls one',
      () async {
        apnsDeliveryProvider.status.value = ApnsStatus.tokenFailed;
        addTearDown(() => apnsDeliveryProvider.status.value = ApnsStatus.idle);
        final container = await start(allowed: true);

        voip.stateValue.value = VoipRegistrationState.failed;

        expect(
          container.read(deliveryFailureProvider)?.action,
          DeliveryFailureAction.retry,
        );
      },
    );

    test('Android never shows it', () async {
      final container = await _container(
        allowed: true,
        mode: 'fcm',
        autoSelected: null,
        capabilities: androidCapabilities,
        voip: voip,
      );

      voip.stateValue.value = VoipRegistrationState.failed;

      expect(container.read(deliveryFailureProvider), isNot(callsSetupFailed));
    });
  });

  group('with Apple push', () {
    tearDown(() {
      apnsDeliveryProvider.status.value = ApnsStatus.idle;
      apnsDeliveryProvider.dropped.value = 0;
    });

    Future<ProviderContainer> applePush() => _container(
      allowed: true,
      mode: 'apns',
      autoSelected: null,
      capabilities: iosCapabilities,
    );

    test('follows the registration as it fails and recovers', () async {
      final container = await applePush();
      expect(container.read(deliveryFailureProvider), isNull);

      apnsDeliveryProvider.status.value = ApnsStatus.tokenFailed;

      expect(
        container.read(deliveryFailureProvider)?.message,
        'Could not set up notifications on this device',
      );

      apnsDeliveryProvider.status.value = ApnsStatus.ready;

      expect(container.read(deliveryFailureProvider), isNull);
    });

    test('follows the drop count while registered', () async {
      apnsDeliveryProvider.status.value = ApnsStatus.ready;
      final container = await applePush();
      expect(container.read(deliveryFailureProvider), isNull);

      apnsDeliveryProvider.dropped.value = 1;

      expect(
        container.read(deliveryFailureProvider)?.message,
        'Notifications may not reach this device',
      );
    });
  });

  group('a dismissed failure', () {
    tearDown(() {
      fcmDeliveryProvider.status.value = FcmStatus.idle;
    });

    Future<ProviderContainer> googleServices() =>
        _container(allowed: true, mode: 'fcm', autoSelected: null);

    bool dismissed(ProviderContainer container) => deliveryFailureIsDismissed(
      container.read(deliveryFailureProvider)!,
      container.read(dismissedDeliveryFailureProvider),
    );

    test('stays dismissed while registration keeps failing', () async {
      final container = await googleServices();
      fcmDeliveryProvider.status.value = FcmStatus.tokenFailed;
      container
          .read(dismissedDeliveryFailureProvider.notifier)
          .dismiss(container.read(deliveryFailureProvider)!);

      fcmDeliveryProvider.status.value = FcmStatus.registering;
      fcmDeliveryProvider.status.value = FcmStatus.tokenFailed;

      expect(dismissed(container), isTrue);
    });

    test('shows again once delivery worked in between, even with the same '
        'message', () async {
      final container = await googleServices();
      fcmDeliveryProvider.status.value = FcmStatus.tokenFailed;
      container
          .read(dismissedDeliveryFailureProvider.notifier)
          .dismiss(container.read(deliveryFailureProvider)!);

      fcmDeliveryProvider.status.value = FcmStatus.ready;
      fcmDeliveryProvider.status.value = FcmStatus.pusherFailed;

      expect(dismissed(container), isFalse);
    });

    test('shows again after the user acts on it', () async {
      final container = await googleServices();
      fcmDeliveryProvider.status.value = FcmStatus.tokenFailed;
      final notifier = container.read(dismissedDeliveryFailureProvider.notifier)
        ..dismiss(container.read(deliveryFailureProvider)!);

      notifier.clear();

      expect(dismissed(container), isFalse);
    });
  });

  group('after the user removes this device', () {
    setUp(() {
      final original = UnifiedPushPlatform.instance;
      UnifiedPushPlatform.instance = FakeUnifiedPush();
      addTearDown(() {
        UnifiedPushPlatform.instance = original;
        fcmDeliveryProvider.removed.value = false;
        unifiedPushDeliveryProvider.removed.value = false;
      });
    });

    for (final (mode, removed) in [
      ('fcm', fcmDeliveryProvider.removed),
      ('unifiedPush', unifiedPushDeliveryProvider.removed),
    ]) {
      test('with $mode follows the removal and the registration after '
          'it', () async {
        final container = await _container(
          allowed: true,
          mode: mode,
          autoSelected: null,
        );
        expect(container.read(deliveryFailureProvider), isNull);

        removed.value = true;

        expect(
          container.read(deliveryFailureProvider)?.message,
          'This device is not registered for notifications',
        );

        removed.value = false;

        expect(container.read(deliveryFailureProvider), isNull);
      });
    }

    test('a removal in another method changes nothing', () async {
      final container = await _container(
        allowed: true,
        mode: 'fcm',
        autoSelected: null,
      );
      expect(container.read(deliveryFailureProvider), isNull);

      unifiedPushDeliveryProvider.removed.value = true;

      expect(container.read(deliveryFailureProvider), isNull);
    });

    test('shows nothing while notifications are off', () async {
      fcmDeliveryProvider.removed.value = true;
      final container = await _container(
        allowed: false,
        mode: 'fcm',
        autoSelected: null,
      );

      expect(container.read(deliveryFailureProvider), isNull);
    });
  });

  group('without Google Play services', () {
    late FakeUnifiedPush distributors;

    setUp(() {
      distributors = FakeUnifiedPush();
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
