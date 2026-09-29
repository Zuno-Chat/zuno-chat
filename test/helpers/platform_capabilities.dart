import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/platform/app_platform.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

final androidCapabilities = capabilitiesFor(AppPlatform.android);

final iosCapabilities = capabilitiesFor(AppPlatform.ios);

PlatformCapabilities capabilitiesLike(
  PlatformCapabilities base, {
  bool? batteryExemption,
  bool? backgroundDataRestriction,
  bool? fullScreenIntent,
  bool? homeScreenShortcuts,
  bool? screenSecurity,
  bool? lockScreenCallUi,
  bool? nativeRingbackTone,
  bool? callForegroundService,
  bool? apnsRegistration,
  bool? nativeIncomingRingUi,
  bool? nativeImageResize,
  bool? nativeVideoTools,
  bool? uploadForegroundService,
  List<NotificationDeliveryMode>? deliveryModes,
  NotificationDeliveryMode? defaultDeliveryMode,
}) => PlatformCapabilities(
  batteryExemption: batteryExemption ?? base.batteryExemption,
  backgroundDataRestriction:
      backgroundDataRestriction ?? base.backgroundDataRestriction,
  fullScreenIntent: fullScreenIntent ?? base.fullScreenIntent,
  foregroundSyncService: base.foregroundSyncService,
  homeScreenShortcuts: homeScreenShortcuts ?? base.homeScreenShortcuts,
  screenSecurity: screenSecurity ?? base.screenSecurity,
  sensitiveClipboard: base.sensitiveClipboard,
  lockScreenCallUi: lockScreenCallUi ?? base.lockScreenCallUi,
  nativeRingbackTone: nativeRingbackTone ?? base.nativeRingbackTone,
  callForegroundService: callForegroundService ?? base.callForegroundService,
  autostartSettings: base.autostartSettings,
  headlessWakeLocks: base.headlessWakeLocks,
  notificationImages: base.notificationImages,
  vibrationPatterns: base.vibrationPatterns,
  playServices: base.playServices,
  deviceSafetyChecks: base.deviceSafetyChecks,
  inboundShare: base.inboundShare,
  nativeSignOutWipe: base.nativeSignOutWipe,
  nativeImageResize: nativeImageResize ?? base.nativeImageResize,
  nativeVideoTools: nativeVideoTools ?? base.nativeVideoTools,
  uploadForegroundService:
      uploadForegroundService ?? base.uploadForegroundService,
  networkAvailabilityEvents: base.networkAvailabilityEvents,
  keyboardLearningOptOut: base.keyboardLearningOptOut,
  apnsRegistration: apnsRegistration ?? base.apnsRegistration,
  nativeIncomingRingUi: nativeIncomingRingUi ?? base.nativeIncomingRingUi,
  playerNeedsMediaType: base.playerNeedsMediaType,
  videoCodecOrder: base.videoCodecOrder,
  recorderWritesOgg: base.recorderWritesOgg,
  callMuteByInputMixer: base.callMuteByInputMixer,
  deliveryModes: deliveryModes ?? base.deliveryModes,
  defaultDeliveryMode: defaultDeliveryMode ?? base.defaultDeliveryMode,
);
