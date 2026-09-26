import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notifications/notification_delivery_mode.dart';
import 'app_platform.dart';

@immutable
class PlatformCapabilities {
  final bool batteryExemption;
  final bool backgroundDataRestriction;
  final bool fullScreenIntent;
  final bool foregroundSyncService;
  final bool homeScreenShortcuts;
  final bool screenSecurity;
  final bool sensitiveClipboard;
  final bool lockScreenCallUi;
  final bool nativeRingbackTone;
  final bool callForegroundService;
  final bool autostartSettings;
  final bool headlessWakeLocks;
  final bool notificationImages;
  final bool vibrationPatterns;
  final bool playServices;
  final bool deviceSafetyChecks;
  final bool inboundShare;
  final bool nativeSignOutWipe;
  final bool nativeImageResize;
  final bool nativeVideoTools;
  final bool uploadForegroundService;
  final bool networkAvailabilityEvents;
  final List<NotificationDeliveryMode> deliveryModes;
  final NotificationDeliveryMode defaultDeliveryMode;

  const PlatformCapabilities({
    required this.batteryExemption,
    required this.backgroundDataRestriction,
    required this.fullScreenIntent,
    required this.foregroundSyncService,
    required this.homeScreenShortcuts,
    required this.screenSecurity,
    required this.sensitiveClipboard,
    required this.lockScreenCallUi,
    required this.nativeRingbackTone,
    required this.callForegroundService,
    required this.autostartSettings,
    required this.headlessWakeLocks,
    required this.notificationImages,
    required this.vibrationPatterns,
    required this.playServices,
    required this.deviceSafetyChecks,
    required this.inboundShare,
    required this.nativeSignOutWipe,
    required this.nativeImageResize,
    required this.nativeVideoTools,
    required this.uploadForegroundService,
    required this.networkAvailabilityEvents,
    required this.deliveryModes,
    required this.defaultDeliveryMode,
  });
}

PlatformCapabilities capabilitiesFor(AppPlatform platform) =>
    switch (platform) {
      AppPlatform.android => const PlatformCapabilities(
        batteryExemption: true,
        backgroundDataRestriction: true,
        fullScreenIntent: true,
        foregroundSyncService: true,
        homeScreenShortcuts: true,
        screenSecurity: true,
        sensitiveClipboard: true,
        lockScreenCallUi: true,
        nativeRingbackTone: true,
        callForegroundService: true,
        autostartSettings: true,
        headlessWakeLocks: true,
        notificationImages: true,
        vibrationPatterns: true,
        playServices: true,
        deviceSafetyChecks: true,
        inboundShare: true,
        nativeSignOutWipe: true,
        nativeImageResize: true,
        nativeVideoTools: true,
        uploadForegroundService: true,
        networkAvailabilityEvents: true,
        deliveryModes: [
          NotificationDeliveryMode.fcm,
          NotificationDeliveryMode.unifiedPush,
          NotificationDeliveryMode.backgroundService,
        ],
        defaultDeliveryMode: NotificationDeliveryMode.fcm,
      ),
      AppPlatform.ios => const PlatformCapabilities(
        batteryExemption: false,
        backgroundDataRestriction: false,
        fullScreenIntent: false,
        foregroundSyncService: false,
        homeScreenShortcuts: false,
        screenSecurity: false,
        sensitiveClipboard: false,
        lockScreenCallUi: false,
        nativeRingbackTone: false,
        callForegroundService: false,
        autostartSettings: false,
        headlessWakeLocks: false,
        notificationImages: false,
        vibrationPatterns: false,
        playServices: false,
        deviceSafetyChecks: false,
        inboundShare: false,
        nativeSignOutWipe: false,
        nativeImageResize: false,
        nativeVideoTools: false,
        uploadForegroundService: false,
        networkAvailabilityEvents: false,
        deliveryModes: [NotificationDeliveryMode.apns],
        defaultDeliveryMode: NotificationDeliveryMode.apns,
      ),
    };

PlatformCapabilities _ambientCapabilities = capabilitiesFor(currentAppPlatform);

PlatformCapabilities get ambientCapabilities => _ambientCapabilities;

@visibleForTesting
set ambientCapabilities(PlatformCapabilities capabilities) =>
    _ambientCapabilities = capabilities;

final platformCapabilitiesProvider = Provider<PlatformCapabilities>(
  (ref) => ambientCapabilities,
);
