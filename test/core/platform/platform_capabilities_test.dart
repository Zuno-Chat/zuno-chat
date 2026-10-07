import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/notifications/background_sync_service.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/platform/app_platform.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/shortcuts/home_screen_shortcut.dart';

class _Capability {
  final String name;

  final Object? Function(PlatformCapabilities capabilities) read;

  final Object? android;

  final Object? ios;

  const _Capability(
    this.name, {
    required this.read,
    required this.android,
    required this.ios,
  });
}

final _capabilities = <_Capability>[
  _Capability(
    'batteryExemption',
    read: (c) => c.batteryExemption,
    android: true,
    ios: false,
  ),
  _Capability(
    'backgroundDataRestriction',
    read: (c) => c.backgroundDataRestriction,
    android: true,
    ios: false,
  ),
  _Capability(
    'fullScreenIntent',
    read: (c) => c.fullScreenIntent,
    android: true,
    ios: false,
  ),
  _Capability(
    'foregroundSyncService',
    read: (c) => c.foregroundSyncService,
    android: true,
    ios: false,
  ),
  _Capability(
    'homeScreenShortcuts',
    read: (c) => c.homeScreenShortcuts,
    android: true,
    ios: false,
  ),
  _Capability(
    'screenSecurity',
    read: (c) => c.screenSecurity,
    android: true,
    ios: true,
  ),
  _Capability(
    'screenshotBlocking',
    read: (c) => c.screenshotBlocking,
    android: true,
    ios: false,
  ),
  _Capability(
    'sensitiveClipboard',
    read: (c) => c.sensitiveClipboard,
    android: true,
    ios: true,
  ),
  _Capability(
    'lockScreenCallUi',
    read: (c) => c.lockScreenCallUi,
    android: true,
    ios: false,
  ),
  _Capability(
    'nativeRingbackTone',
    read: (c) => c.nativeRingbackTone,
    android: true,
    ios: false,
  ),
  _Capability(
    'callForegroundService',
    read: (c) => c.callForegroundService,
    android: true,
    ios: false,
  ),
  _Capability(
    'autostartSettings',
    read: (c) => c.autostartSettings,
    android: true,
    ios: false,
  ),
  _Capability(
    'headlessWakeLocks',
    read: (c) => c.headlessWakeLocks,
    android: true,
    ios: true,
  ),
  _Capability(
    'notificationImages',
    read: (c) => c.notificationImages,
    android: true,
    ios: false,
  ),
  _Capability(
    'vibrationPatterns',
    read: (c) => c.vibrationPatterns,
    android: true,
    ios: false,
  ),
  _Capability(
    'deviceSafetyChecks',
    read: (c) => c.deviceSafetyChecks,
    android: true,
    ios: false,
  ),
  _Capability(
    'inboundShare',
    read: (c) => c.inboundShare,
    android: true,
    ios: true,
  ),
  _Capability(
    'nativeSignOutWipe',
    read: (c) => c.nativeSignOutWipe,
    android: true,
    ios: true,
  ),
  _Capability(
    'nativeImageResize',
    read: (c) => c.nativeImageResize,
    android: true,
    ios: true,
  ),
  _Capability(
    'nativeVideoTools',
    read: (c) => c.nativeVideoTools,
    android: true,
    ios: true,
  ),
  _Capability(
    'uploadForegroundService',
    read: (c) => c.uploadForegroundService,
    android: true,
    ios: true,
  ),
  _Capability(
    'networkAvailabilityEvents',
    read: (c) => c.networkAvailabilityEvents,
    android: true,
    ios: true,
  ),
  _Capability(
    'keyboardLearningOptOut',
    read: (c) => c.keyboardLearningOptOut,
    android: true,
    ios: false,
  ),
  _Capability(
    'locationServicesSettings',
    read: (c) => c.locationServicesSettings,
    android: true,
    ios: false,
  ),
  _Capability(
    'filesTypedByExtension',
    read: (c) => c.filesTypedByExtension,
    android: false,
    ios: true,
  ),
  _Capability(
    'atomicDatabaseBatches',
    read: (c) => c.atomicDatabaseBatches,
    android: true,
    ios: false,
  ),
  _Capability(
    'nativeRoomOpens',
    read: (c) => c.nativeRoomOpens,
    android: true,
    ios: true,
  ),
  _Capability(
    'clientLease',
    read: (c) => c.clientLease,
    android: true,
    ios: true,
  ),
  _Capability(
    'instantPushNotices',
    read: (c) => c.instantPushNotices,
    android: true,
    ios: false,
  ),
  _Capability(
    'notificationAvatars',
    read: (c) => c.notificationAvatars,
    android: true,
    ios: false,
  ),
  _Capability(
    'signOutWipeKeepsProcess',
    read: (c) => c.signOutWipeKeepsProcess,
    android: false,
    ios: true,
  ),
  _Capability(
    'callMuteByInputMixer',
    read: (c) => c.callMuteByInputMixer,
    android: false,
    ios: true,
  ),
  _Capability(
    'recorderWritesOgg',
    read: (c) => c.recorderWritesOgg,
    android: true,
    ios: false,
  ),
  _Capability(
    'videoCodecOrder',
    read: (c) => c.videoCodecOrder,
    android: ['video/VP8', 'video/H264'],
    ios: null,
  ),
  _Capability(
    'playerNeedsMediaType',
    read: (c) => c.playerNeedsMediaType,
    android: false,
    ios: true,
  ),
  _Capability(
    'apnsRegistration',
    read: (c) => c.apnsRegistration,
    android: false,
    ios: true,
  ),
  _Capability(
    'nativeIncomingRingUi',
    read: (c) => c.nativeIncomingRingUi,
    android: true,
    ios: false,
  ),
  _Capability('callKit', read: (c) => c.callKit, android: false, ios: true),
  _Capability(
    'pictureInPicture',
    read: (c) => c.pictureInPicture,
    android: true,
    ios: true,
  ),
  _Capability(
    'pushDiagnostics',
    read: (c) => c.pushDiagnostics,
    android: true,
    ios: true,
  ),
  _Capability('voipRing', read: (c) => c.voipRing, android: false, ios: true),
  _Capability(
    'nseNotifications',
    read: (c) => c.nseNotifications,
    android: false,
    ios: true,
  ),
  _Capability(
    'nativeNotificationActions',
    read: (c) => c.nativeNotificationActions,
    android: false,
    ios: true,
  ),
  _Capability(
    'videoRendererNeedsDetach',
    read: (c) => c.videoRendererNeedsDetach,
    android: false,
    ios: true,
  ),
  _Capability(
    'cameraStopsInBackground',
    read: (c) => c.cameraStopsInBackground,
    android: false,
    ios: true,
  ),
  _Capability(
    'externalPaymentLinks',
    read: (c) => c.externalPaymentLinks,
    android: true,
    ios: false,
  ),
  _Capability(
    'deliveryModes',
    read: (c) => c.deliveryModes,
    android: [
      NotificationDeliveryMode.fcm,
      NotificationDeliveryMode.unifiedPush,
      NotificationDeliveryMode.backgroundService,
    ],
    ios: [NotificationDeliveryMode.apns],
  ),
  _Capability(
    'defaultDeliveryMode',
    read: (c) => c.defaultDeliveryMode,
    android: NotificationDeliveryMode.fcm,
    ios: NotificationDeliveryMode.apns,
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('each capability is set per platform', () {
    for (final capability in _capabilities) {
      test(capability.name, () {
        expect(
          capability.read(capabilitiesFor(AppPlatform.android)),
          capability.android,
          reason: '${capability.name} on android',
        );
        expect(
          capability.read(capabilitiesFor(AppPlatform.ios)),
          capability.ios,
          reason: '${capability.name} on ios',
        );
      });
    }
  });

  test('each platform offers its own default delivery mode', () {
    for (final platform in AppPlatform.values) {
      final capabilities = capabilitiesFor(platform);
      expect(
        capabilities.deliveryModes,
        contains(capabilities.defaultDeliveryMode),
        reason: '$platform',
      );
    }
  });

  test('every delivery mode is offered on some platform', () {
    expect({
      for (final p in AppPlatform.values) ...capabilitiesFor(p).deliveryModes,
    }, NotificationDeliveryMode.values.toSet());
  });

  test('each platform always gets the same capabilities instance', () {
    for (final platform in AppPlatform.values) {
      expect(
        capabilitiesFor(platform),
        same(capabilitiesFor(platform)),
        reason: '$platform',
      );
    }
  });

  test('a host that is not iOS, like the test host, resolves to android', () {
    expect(currentAppPlatform, AppPlatform.android);
  });

  group('platformCapabilitiesProvider', () {
    test('serves the android capabilities by default', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(platformCapabilitiesProvider),
        same(capabilitiesFor(AppPlatform.android)),
      );
    });

    test('serves an override instead of the host platform', () {
      final ios = capabilitiesFor(AppPlatform.ios);
      final container = ProviderContainer(
        overrides: [platformCapabilitiesProvider.overrideWithValue(ios)],
      );
      addTearDown(container.dispose);

      expect(container.read(platformCapabilitiesProvider), same(ios));
    });
  });

  group('ambientCapabilities', () {
    final android = capabilitiesFor(AppPlatform.android);
    final ios = capabilitiesFor(AppPlatform.ios);
    const nativeChannels = [
      MethodChannel('zuno/background_sync'),
      MethodChannel('zuno/shortcuts'),
    ];
    const nativeCalls = [
      'zuno/background_sync startBackgroundSyncService',
      'zuno/shortcuts pinShortcut',
    ];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late List<String> calls;

    setUp(() {
      calls = [];
      for (final channel in nativeChannels) {
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add('${channel.name} ${call.method}');
          return null;
        });
      }
    });

    tearDown(() {
      for (final channel in nativeChannels) {
        messenger.setMockMethodCallHandler(channel, null);
      }
    });

    PlatformCapabilities providerCapabilities() {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      return container.read(platformCapabilitiesProvider);
    }

    Future<void> useSingletonConsumers() async {
      await BackgroundSyncService.instance.start();
      await pinRoomShortcut(roomId: '!room:example.org', label: 'Room');
    }

    test('is the host platform by default, for every consumer', () async {
      expect(ambientCapabilities, same(android));
      expect(providerCapabilities(), same(android));

      await useSingletonConsumers();

      expect(calls, nativeCalls);
    });

    test(
      'set to iOS, reaches provider and singleton consumers alike',
      () async {
        ambientCapabilities = ios;

        expect(providerCapabilities(), same(ios));

        await useSingletonConsumers();

        expect(calls, isEmpty);
      },
    );

    test('is back to the host platform in the next test', () async {
      expect(ambientCapabilities, same(android));
      expect(providerCapabilities(), same(android));

      await useSingletonConsumers();

      expect(calls, nativeCalls);
    });

    test('loses to capabilities that are injected or overridden', () async {
      ambientCapabilities = ios;
      final container = ProviderContainer(
        overrides: [platformCapabilitiesProvider.overrideWithValue(android)],
      );
      addTearDown(container.dispose);

      expect(container.read(platformCapabilitiesProvider), same(android));

      await BackgroundSyncService(capabilities: android).start();
      await pinRoomShortcut(
        roomId: '!room:example.org',
        label: 'Room',
        capabilities: android,
      );

      expect(calls, nativeCalls);
    });
  });
}
