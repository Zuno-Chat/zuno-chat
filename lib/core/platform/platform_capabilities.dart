import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../location/maps_link.dart';
import '../push/delivery/notification_delivery_mode.dart';
import 'app_platform.dart';

enum AppLanguageSetting { inApp, systemSettings }

@immutable
class PlatformCapabilities {
  final bool batteryExemption;
  final bool backgroundDataRestriction;
  final bool fullScreenIntent;
  final bool foregroundSyncService;
  final bool homeScreenShortcuts;
  final bool screenSecurity;
  final bool screenshotBlocking;
  final bool sensitiveClipboard;
  final bool lockScreenCallUi;
  final bool nativeCallAudio;
  final bool callForegroundService;
  final bool autostartSettings;
  final bool headlessWakeLocks;
  final bool notificationImages;
  final bool vibrationPatterns;
  final bool deviceSafetyChecks;
  final bool inboundShare;
  final bool nativeSignOutWipe;
  final bool nativeImageResize;
  final bool nativeVideoTools;
  final bool uploadForegroundService;
  final bool networkAvailabilityEvents;
  final bool keyboardLearningOptOut;
  final bool thirdPartyKeyboardBlocking;
  final bool overlayHiding;
  final bool accessibilitySensitivity;
  final bool apnsRegistration;
  final bool nativeIncomingRingUi;
  final bool callKit;
  final bool pictureInPicture;
  final bool playerNeedsMediaType;
  final List<String>? videoCodecOrder;
  final bool recorderWritesOgg;
  final bool callMuteByInputMixer;
  final bool signOutWipeKeepsProcess;
  final bool locationServicesSettings;
  final bool atomicDatabaseBatches;
  final bool nativeRoomOpens;
  final bool clientLease;
  final bool instantPushNotices;
  final bool notificationAvatars;
  final bool pushDiagnostics;
  final bool voipRing;
  final bool nseNotifications;
  final bool nativeNotificationActions;
  final bool notificationRetentionCheck;
  final bool videoRendererNeedsDetach;
  final bool cameraStopsInBackground;
  final bool externalPaymentLinks;
  final bool nativeSensitiveFileExport;
  final bool nativeFileShare;
  final bool audioPlayerNeedsFile;
  final bool liveLocation;
  final bool nativeLogFloor;
  final AppLanguageSetting appLanguage;
  final MapsApp mapsApp;
  final List<NotificationDeliveryMode> deliveryModes;
  final NotificationDeliveryMode defaultDeliveryMode;

  const PlatformCapabilities({
    required this.batteryExemption,
    required this.backgroundDataRestriction,
    required this.fullScreenIntent,
    required this.foregroundSyncService,
    required this.homeScreenShortcuts,
    required this.screenSecurity,
    required this.screenshotBlocking,
    required this.sensitiveClipboard,
    required this.lockScreenCallUi,
    required this.nativeCallAudio,
    required this.callForegroundService,
    required this.autostartSettings,
    required this.headlessWakeLocks,
    required this.notificationImages,
    required this.vibrationPatterns,
    required this.deviceSafetyChecks,
    required this.inboundShare,
    required this.nativeSignOutWipe,
    required this.nativeImageResize,
    required this.nativeVideoTools,
    required this.uploadForegroundService,
    required this.networkAvailabilityEvents,
    required this.keyboardLearningOptOut,
    required this.thirdPartyKeyboardBlocking,
    required this.overlayHiding,
    required this.accessibilitySensitivity,
    required this.apnsRegistration,
    required this.nativeIncomingRingUi,
    required this.callKit,
    required this.pictureInPicture,
    required this.playerNeedsMediaType,
    required this.videoCodecOrder,
    required this.recorderWritesOgg,
    required this.callMuteByInputMixer,
    required this.signOutWipeKeepsProcess,
    required this.locationServicesSettings,
    required this.atomicDatabaseBatches,
    required this.nativeRoomOpens,
    required this.clientLease,
    required this.instantPushNotices,
    required this.notificationAvatars,
    required this.pushDiagnostics,
    required this.voipRing,
    required this.nseNotifications,
    required this.nativeNotificationActions,
    required this.notificationRetentionCheck,
    required this.videoRendererNeedsDetach,
    required this.cameraStopsInBackground,
    required this.externalPaymentLinks,
    required this.nativeSensitiveFileExport,
    required this.nativeFileShare,
    required this.audioPlayerNeedsFile,
    required this.liveLocation,
    required this.nativeLogFloor,
    required this.appLanguage,
    required this.mapsApp,
    required this.deliveryModes,
    required this.defaultDeliveryMode,
  });

  bool get incognitoKeyboard =>
      keyboardLearningOptOut || thirdPartyKeyboardBlocking;
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
        screenshotBlocking: true,
        sensitiveClipboard: true,
        lockScreenCallUi: true,
        nativeCallAudio: true,
        callForegroundService: true,
        autostartSettings: true,
        headlessWakeLocks: true,
        notificationImages: true,
        vibrationPatterns: true,
        deviceSafetyChecks: true,
        inboundShare: true,
        nativeSignOutWipe: true,
        nativeImageResize: true,
        nativeVideoTools: true,
        uploadForegroundService: true,
        networkAvailabilityEvents: true,
        keyboardLearningOptOut: true,
        thirdPartyKeyboardBlocking: false,
        overlayHiding: true,
        accessibilitySensitivity: true,
        apnsRegistration: false,
        nativeIncomingRingUi: true,
        callKit: false,
        pictureInPicture: true,
        playerNeedsMediaType: false,
        videoCodecOrder: ['video/VP8', 'video/H264'],
        recorderWritesOgg: true,
        callMuteByInputMixer: false,
        signOutWipeKeepsProcess: false,
        locationServicesSettings: true,
        atomicDatabaseBatches: true,
        nativeRoomOpens: true,
        clientLease: true,
        instantPushNotices: true,
        notificationAvatars: true,
        pushDiagnostics: true,
        voipRing: false,
        nseNotifications: false,
        nativeNotificationActions: false,
        notificationRetentionCheck: false,
        videoRendererNeedsDetach: false,
        cameraStopsInBackground: false,
        externalPaymentLinks: true,
        nativeSensitiveFileExport: false,
        nativeFileShare: true,
        audioPlayerNeedsFile: false,
        liveLocation: true,
        nativeLogFloor: true,
        appLanguage: AppLanguageSetting.inApp,
        mapsApp: MapsApp.geoIntent,
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
        screenSecurity: true,
        screenshotBlocking: false,
        sensitiveClipboard: true,
        lockScreenCallUi: false,
        nativeCallAudio: false,
        callForegroundService: false,
        autostartSettings: false,
        headlessWakeLocks: true,
        notificationImages: false,
        vibrationPatterns: false,
        deviceSafetyChecks: false,
        inboundShare: true,
        nativeSignOutWipe: true,
        nativeImageResize: true,
        nativeVideoTools: true,
        uploadForegroundService: true,
        networkAvailabilityEvents: true,
        keyboardLearningOptOut: false,
        thirdPartyKeyboardBlocking: true,
        overlayHiding: false,
        accessibilitySensitivity: false,
        apnsRegistration: true,
        nativeIncomingRingUi: false,
        callKit: true,
        pictureInPicture: true,
        playerNeedsMediaType: true,
        videoCodecOrder: null,
        recorderWritesOgg: false,
        callMuteByInputMixer: true,
        signOutWipeKeepsProcess: true,
        locationServicesSettings: false,
        atomicDatabaseBatches: false,
        nativeRoomOpens: true,
        clientLease: true,
        instantPushNotices: false,
        notificationAvatars: false,
        pushDiagnostics: true,
        voipRing: true,
        nseNotifications: true,
        nativeNotificationActions: true,
        notificationRetentionCheck: true,
        videoRendererNeedsDetach: true,
        cameraStopsInBackground: true,
        externalPaymentLinks: false,
        nativeSensitiveFileExport: true,
        nativeFileShare: false,
        audioPlayerNeedsFile: true,
        liveLocation: true,
        nativeLogFloor: false,
        appLanguage: AppLanguageSetting.systemSettings,
        mapsApp: MapsApp.appleMaps,
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

final operatingSystemVersionProvider = Provider<String>(
  (ref) => Platform.operatingSystemVersion,
);
