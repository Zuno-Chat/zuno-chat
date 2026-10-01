import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unifiedpush/unifiedpush.dart';
import 'package:unifiedpush_platform_interface/unifiedpush_platform_interface.dart';

import 'package:zuno/core/notifications/delivery_auto_fallback.dart';
import 'package:zuno/core/notifications/fcm_delivery_provider.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/push/fcm_bridge.dart';
import 'package:zuno/core/push/fcm_registration_store.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

import '../../helpers/fake_matrix.dart';

class _FakeUnifiedPush extends UnifiedPushPlatform {
  List<String> installed = const [];

  @override
  Future<List<String>> getDistributors(List<String> features) async =>
      installed;

  @override
  Future<String?> getDistributor() async => null;

  @override
  Future<bool> tryUseCurrentOrDefaultDistributor() async => false;

  @override
  Future<void> initializeCallback({
    void Function(PushEndpoint endpoint, String instance)? onNewEndpoint,
    void Function(FailedReason reason, String instance)? onRegistrationFailed,
    void Function(String instance)? onUnregistered,
    void Function(PushMessage message, String instance)? onMessage,
  }) async {}

  @override
  Future<void> initializeOnTempUnavailable(
    void Function(String instance)? onTempUnavailable,
  ) async {}

  @override
  Future<void> register(
    String instance,
    List<String> features,
    String? messageForDistributor,
    String? vapid,
  ) async {}

  @override
  Future<void> saveDistributor(String distributor) async {}

  @override
  Future<void> unregister(String instance) async {}

  @override
  void setLinuxOptions(LinuxOptions options) {}
}

void main() {
  group('autoFallbackFor', () {
    test('picks UnifiedPush when Play Services is missing and a '
        'distributor is installed', () {
      expect(
        autoFallbackFor(
          fcm: FcmStatus.playServicesUnavailable,
          fcmRegistered: false,
          userChoseMode: false,
          hasDistributor: true,
        ),
        NotificationDeliveryMode.unifiedPush,
      );
    });

    test(
      'falls back to background sync when there is no distributor either',
      () {
        expect(
          autoFallbackFor(
            fcm: FcmStatus.playServicesUnavailable,
            fcmRegistered: false,
            userChoseMode: false,
            hasDistributor: false,
          ),
          NotificationDeliveryMode.backgroundService,
        );
      },
    );

    for (final status in [
      FcmStatus.playServicesDisabled,
      FcmStatus.notConfigured,
    ]) {
      test('switches away when ${status.name}, like a missing Google Play '
          'services', () {
        expect(
          autoFallbackFor(
            fcm: status,
            fcmRegistered: false,
            userChoseMode: false,
            hasDistributor: true,
          ),
          NotificationDeliveryMode.unifiedPush,
        );
        expect(
          autoFallbackFor(
            fcm: status,
            fcmRegistered: false,
            userChoseMode: true,
            hasDistributor: true,
          ),
          isNull,
        );
      });
    }

    test('never overrides a mode the user chose', () {
      expect(
        autoFallbackFor(
          fcm: FcmStatus.playServicesUnavailable,
          fcmRegistered: false,
          userChoseMode: true,
          hasDistributor: true,
        ),
        isNull,
      );
    });

    test('never moves a device that holds a Google services registration, '
        'whatever the device reports', () {
      for (final status in [
        FcmStatus.playServicesUnavailable,
        FcmStatus.playServicesDisabled,
        FcmStatus.notConfigured,
      ]) {
        expect(
          autoFallbackFor(
            fcm: status,
            fcmRegistered: true,
            userChoseMode: false,
            hasDistributor: true,
          ),
          isNull,
          reason: '$status',
        );
      }
    });

    test('an update-required or transient state is not a reason to switch', () {
      for (final status in [
        FcmStatus.playServicesUpdateRequired,
        FcmStatus.tokenFailed,
        FcmStatus.pusherFailed,
        FcmStatus.ready,
      ]) {
        expect(
          autoFallbackFor(
            fcm: status,
            fcmRegistered: false,
            userChoseMode: false,
            hasDistributor: true,
          ),
          isNull,
          reason: '$status',
        );
      }
    });
  });

  group('deliveryAutoFallbackProvider', () {
    late _FakeUnifiedPush fake;
    late ProviderContainer container;

    setUp(() async {
      fake = _FakeUnifiedPush();
      UnifiedPushPlatform.instance = fake;
      fcmDeliveryProvider.status.value = FcmStatus.idle;
      addTearDown(() => fcmDeliveryProvider.status.value = FcmStatus.idle);
    });

    Future<void> build() async {
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      container.read(deliveryAutoFallbackProvider);
    }

    test('switches an untouched default to UnifiedPush and remembers that '
        'it did so', () async {
      fake.installed = ['io.heckel.ntfy'];
      await build();

      fcmDeliveryProvider.status.value = FcmStatus.playServicesUnavailable;
      await pumpEventQueue();

      expect(
        container.read(notificationDeliveryModeProvider),
        NotificationDeliveryMode.unifiedPush,
      );
      expect(
        container.read(autoSelectedDeliveryModeProvider),
        NotificationDeliveryMode.unifiedPush,
      );
    });

    test('keeps a device whose Google services registration is in place on '
        'Google services when Google Play services turns off', () async {
      fake.installed = ['io.heckel.ntfy'];
      await build();
      await saveFcmRegistration(
        await SharedPreferences.getInstance(),
        token: 'token-abc',
      );
      final provider = fcmDeliveryProvider;
      final seams = (
        provider.availabilityReader,
        provider.notificationsAllowed,
        provider.tokenDeleter,
      );
      provider
        ..availabilityReader = (() async => FcmAvailability.disabled)
        ..notificationsAllowed = (() async => true)
        ..tokenDeleter = (() async {});
      final client = buildTestClient();
      addTearDown(() async {
        await provider.stop(client);
        provider
          ..availabilityReader = seams.$1
          ..notificationsAllowed = seams.$2
          ..tokenDeleter = seams.$3;
      });

      await provider.start(client);
      await pumpEventQueue();

      expect(provider.status.value, FcmStatus.playServicesDisabled);
      expect(
        container.read(notificationDeliveryModeProvider),
        NotificationDeliveryMode.fcm,
      );
      expect(container.read(autoSelectedDeliveryModeProvider), isNull);
    });

    test('leaves a mode the user set alone', () async {
      fake.installed = ['io.heckel.ntfy'];
      await build();
      await container
          .read(notificationDeliveryModeProvider.notifier)
          .set(NotificationDeliveryMode.fcm);

      fcmDeliveryProvider.status.value = FcmStatus.playServicesUnavailable;
      await pumpEventQueue();

      expect(
        container.read(notificationDeliveryModeProvider),
        NotificationDeliveryMode.fcm,
      );
      expect(container.read(autoSelectedDeliveryModeProvider), isNull);
    });

    test(
      'acknowledging the switch clears the notice but keeps the mode',
      () async {
        fake.installed = ['io.heckel.ntfy'];
        await build();
        fcmDeliveryProvider.status.value = FcmStatus.playServicesUnavailable;
        await pumpEventQueue();

        await container
            .read(autoSelectedDeliveryModeProvider.notifier)
            .acknowledge();

        expect(container.read(autoSelectedDeliveryModeProvider), isNull);
        expect(
          container.read(notificationDeliveryModeProvider),
          NotificationDeliveryMode.unifiedPush,
        );
      },
    );
  });
}
