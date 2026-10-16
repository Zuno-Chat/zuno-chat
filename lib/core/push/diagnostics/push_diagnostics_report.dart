import 'package:flutter/foundation.dart' show immutable, listEquals;

import '../../../features/settings/presentation/fcm_status_display.dart'
    show fcmStatusLabel;
import '../../../features/settings/presentation/unified_push_status_display.dart'
    show unifiedPushStatusLabel;
import '../../brand.dart';
import '../../calls/notifications/call_notification_service.dart'
    show alertingMessageChannelIds, ringChannelIds;
import '../../errors/crash_scrubber.dart';
import '../../format/date_labels.dart';
import '../../l10n/l10n.dart';
import '../../platform/platform_capabilities.dart';
import '../apns/apns_pusher.dart';
import '../delivery/notification_delivery_mode.dart';
import '../fcm/fcm_bridge.dart' show FcmAvailability;
import '../fcm/fcm_delivery_provider.dart' show FcmStatus;
import '../pushers/pusher_format.dart';
import '../pushers/pusher_info.dart';
import '../unified_push/unified_push_delivery_provider.dart'
    show UnifiedPushStatus;
import '../voip/voip_registration.dart';
import 'push_delivery_log.dart';
import 'push_diagnostics_data.dart';
import 'ring_mismatch.dart';

enum DiagnosticStatus { ok, warning, problem, info }

@immutable
class DiagnosticRow {
  const DiagnosticRow(
    this.label,
    this.value, [
    this.status = DiagnosticStatus.info,
  ]);

  final String label;
  final String value;
  final DiagnosticStatus status;

  @override
  bool operator ==(Object other) =>
      other is DiagnosticRow &&
      other.label == label &&
      other.value == value &&
      other.status == status;

  @override
  int get hashCode => Object.hash(label, value, status);

  @override
  String toString() => 'DiagnosticRow($label, $value, ${status.name})';
}

@immutable
class DiagnosticSection {
  const DiagnosticSection(this.title, this.rows);

  final String title;
  final List<DiagnosticRow> rows;

  DiagnosticRow? row(String label) =>
      rows.where((row) => row.label == label).firstOrNull;
}

@immutable
class PushDiagnosticsInputs {
  const PushDiagnosticsInputs({
    required this.capabilities,
    required this.now,
    required this.appVersion,
    this.snapshot = PushDiagnosticsSnapshot.empty,
    this.voip,
    this.health,
    this.reach = ServerReach.unreachable,
    this.pushers,
    this.currentPushkey,
    this.expectedGateway,
    this.deliveryMode = NotificationDeliveryMode.apns,
    this.fcmStatus,
    this.unifiedPushStatus,
    this.playServices,
    this.deliveries,
    this.droppedRegistrations,
    this.voipRefusal,
  });

  final PlatformCapabilities capabilities;
  final DateTime now;
  final String appVersion;
  final PushDiagnosticsSnapshot snapshot;
  final VoipDeviceStatus? voip;
  final ServerHealth? health;
  final ServerReach reach;
  final List<PusherInfo>? pushers;
  final String? currentPushkey;
  final Uri? expectedGateway;
  final NotificationDeliveryMode deliveryMode;
  final FcmStatus? fcmStatus;
  final UnifiedPushStatus? unifiedPushStatus;
  final FcmAvailability? playServices;
  final List<PushDeliveryRecord>? deliveries;
  final int? droppedRegistrations;
  final VoipRefusal? voipRefusal;
}

List<DiagnosticSection> buildPushDiagnostics(
  PushDiagnosticsInputs inputs,
  DateLabels labels,
) {
  final l10n = labels.l10n;
  return [
    if (inputs.capabilities.apnsRegistration) ...[
      _permission(l10n, inputs.snapshot.settings),
      _device(l10n, inputs),
    ] else ...[
      _androidPermission(l10n, inputs),
      _androidDevice(l10n, inputs),
    ],
    if (inputs.capabilities.voipRing) _calls(labels, inputs),
    if (inputs.capabilities.nseNotifications) _extension(labels, inputs),
    _delivery(labels, inputs),
    if (inputs.snapshot.metrics.isNotEmpty) _reports(labels, inputs),
  ];
}

bool sameBuild(String a, String b) {
  List<String> numbers(String version) => [
    for (final match in RegExp(r'\d+(?:\.\d+)*').allMatches(version)) match[0]!,
  ];
  return listEquals(numbers(a), numbers(b));
}

final _urlPattern = RegExp(r'https?://\S+');
final _longTokenPattern = RegExp(r'[A-Za-z0-9+/=_-]{32,}');

String redactDiagnostics(String text) =>
    scrubText(text)!
        .replaceAll(_urlPattern, '[redacted]')
        .replaceAll(_longTokenPattern, '[redacted]');

String redactedDiagnosticsText(
  AppLocalizations l10n,
  List<DiagnosticSection> sections, {
  required DateTime now,
  required String appVersion,
}) {
  final buffer = StringBuffer()
    ..writeln(l10n.diagnosticsReportTitle)
    ..writeln('$zunoName $appVersion, ${now.toUtc().toIso8601String()}');
  for (final section in sections) {
    buffer
      ..writeln()
      ..writeln(section.title);
    for (final row in section.rows) {
      buffer.writeln('- ${row.label}: ${row.value.replaceAll('\n', '\n  ')}');
    }
  }
  return redactDiagnostics(buffer.toString());
}

const _settingOrder = [
  'authorization',
  'alert',
  'alertStyle',
  'sound',
  'badge',
  'lockScreen',
  'notificationCenter',
  'showPreviews',
  'timeSensitive',
  'scheduledDelivery',
  'directMessages',
  'announcement',
  'carPlay',
  'criticalAlert',
  'providesAppSettings',
];

String _settingLabel(AppLocalizations l10n, String key) => switch (key) {
  'authorization' => l10n.diagnosticsLabelNotifications,
  'alert' => l10n.diagnosticsSettingAlerts,
  'alertStyle' => l10n.diagnosticsSettingBannerStyle,
  'sound' => l10n.diagnosticsSettingSounds,
  'badge' => l10n.diagnosticsSettingBadges,
  'lockScreen' => l10n.diagnosticsSettingLockScreen,
  'notificationCenter' => l10n.diagnosticsSettingNotificationCenter,
  'showPreviews' => l10n.diagnosticsSettingShowPreviews,
  'timeSensitive' => l10n.diagnosticsSettingTimeSensitive,
  'scheduledDelivery' => l10n.diagnosticsSettingScheduledSummary,
  'directMessages' => l10n.diagnosticsSettingDirectMessages,
  'announcement' => l10n.diagnosticsSettingAnnounce,
  'carPlay' => l10n.diagnosticsSettingCarPlay,
  'criticalAlert' => l10n.diagnosticsSettingCriticalAlerts,
  'providesAppSettings' => l10n.diagnosticsSettingSettingsLink,
  _ => key,
};

String _settingValue(AppLocalizations l10n, String value) => switch (value) {
  'authorized' => l10n.diagnosticsAllowed,
  'denied' => l10n.diagnosticsNotAllowed,
  'notDetermined' => l10n.diagnosticsValueNotAskedYet,
  'provisional' => l10n.diagnosticsValueDeliveredQuietly,
  'ephemeral' => l10n.diagnosticsValueAllowedForNow,
  'enabled' => l10n.diagnosticsOn,
  'disabled' => l10n.diagnosticsOff,
  'notSupported' => l10n.diagnosticsValueNotAvailable,
  'unknown' => l10n.diagnosticsUnknown,
  'none' => l10n.diagnosticsNone,
  'banner' => l10n.diagnosticsValueTemporary,
  'alert' => l10n.diagnosticsValuePersistent,
  'always' => l10n.diagnosticsValueAlways,
  'whenAuthenticated' => l10n.diagnosticsValueWhenUnlocked,
  'never' => l10n.diagnosticsNever,
  'true' => l10n.diagnosticsYes,
  'false' => l10n.diagnosticsNo,
  _ => value,
};

DiagnosticStatus _settingStatus(String key, String value) =>
    switch ((key, value)) {
      ('authorization', 'authorized') => DiagnosticStatus.ok,
      ('authorization', 'denied') => DiagnosticStatus.problem,
      ('authorization', _) => DiagnosticStatus.warning,
      ('alert', 'disabled') => DiagnosticStatus.problem,
      ('scheduledDelivery', 'enabled') => DiagnosticStatus.warning,
      _ => DiagnosticStatus.info,
    };

String _reportLabel(AppLocalizations l10n, String kind) => switch (kind) {
  'exits' => l10n.diagnosticsReportExits,
  'crash' => l10n.diagnosticsReportCrashes,
  'memory' => l10n.diagnosticsReportMemory,
  _ => kind,
};

String _countLabel(AppLocalizations l10n, String key) => switch (key) {
  'locked_file' => l10n.diagnosticsCountLockedFile,
  'memory' => l10n.diagnosticsCountMemory,
  'watchdog' => l10n.diagnosticsCountWatchdog,
  'task_timeout' => l10n.diagnosticsCountTaskTimeout,
  'cpu' => l10n.diagnosticsCountCpu,
  'bad_access' => l10n.diagnosticsCountBadAccess,
  'abnormal' => l10n.diagnosticsCountAbnormal,
  'pushkit_unreported' => l10n.diagnosticsCountPushkitUnreported,
  'extension_memory' => l10n.diagnosticsCountExtensionMemory,
  _ => key,
};

DiagnosticSection _permission(
  AppLocalizations l10n,
  Map<String, String> settings,
) {
  final title = l10n.diagnosticsSectionPermission;
  if (settings.isEmpty) {
    return DiagnosticSection(title, [
      DiagnosticRow(
        l10n.diagnosticsLabelSettings,
        l10n.diagnosticsSettingsNotAvailable,
        DiagnosticStatus.warning,
      ),
    ]);
  }
  final keys = [
    ..._settingOrder.where(settings.containsKey),
    ...settings.keys.where((key) => !_settingOrder.contains(key)),
  ];
  return DiagnosticSection(title, [
    for (final key in keys)
      DiagnosticRow(
        _settingLabel(l10n, key),
        _settingValue(l10n, settings[key]!),
        _settingStatus(key, settings[key]!),
      ),
  ]);
}

DiagnosticSection _device(AppLocalizations l10n, PushDiagnosticsInputs inputs) {
  final environment = inputs.voip?.environment ?? inputs.snapshot.environment;
  final expectedAppId = switch (environment) {
    'production' => apnsProductionAppId,
    'development' => apnsDevelopmentAppId,
    _ => null,
  };
  final current = _currentPusher(inputs);
  final registeredAppId = current?.appId;
  final appIdLabel = l10n.diagnosticsLabelAppId;
  return DiagnosticSection(l10n.diagnosticsSectionDevice, [
    DiagnosticRow(l10n.diagnosticsLabelEnvironment, switch (environment) {
      'production' => l10n.diagnosticsEnvironmentProduction,
      'development' => l10n.diagnosticsEnvironmentDevelopment,
      _ => l10n.diagnosticsUnknown,
    }, environment == null ? DiagnosticStatus.warning : DiagnosticStatus.info),
    if (expectedAppId != null)
      registeredAppId == null || registeredAppId == expectedAppId
          ? DiagnosticRow(appIdLabel, expectedAppId)
          : DiagnosticRow(
              appIdLabel,
              l10n.diagnosticsAppIdMismatch(registeredAppId, expectedAppId),
              DiagnosticStatus.problem,
            ),
    ..._registrationRows(l10n, inputs, current),
    if (inputs.snapshot.registeredForRemoteNotifications case final token?)
      DiagnosticRow(
        l10n.diagnosticsLabelDeviceToken,
        token ? l10n.diagnosticsReceived : l10n.diagnosticsNotReceived,
        token ? DiagnosticStatus.ok : DiagnosticStatus.problem,
      ),
    if (inputs.droppedRegistrations case final dropped?)
      DiagnosticRow(
        l10n.diagnosticsLabelDroppedRegistrations,
        l10n.commonCount(dropped),
        dropped > 0 ? DiagnosticStatus.warning : DiagnosticStatus.info,
      ),
    DiagnosticRow(l10n.diagnosticsLabelZunoVersion, inputs.appVersion),
  ]);
}

PusherInfo? _currentPusher(PushDiagnosticsInputs inputs) {
  final pushkey = inputs.currentPushkey;
  final pushers = inputs.pushers;
  if (pushkey == null || pushers == null) return null;
  return pushers.where((pusher) => pusher.pushkey == pushkey).firstOrNull;
}

List<DiagnosticRow> _registrationRows(
  AppLocalizations l10n,
  PushDiagnosticsInputs inputs,
  PusherInfo? current,
) => [
  inputs.currentPushkey == null
      ? DiagnosticRow(
          l10n.diagnosticsLabelPushKey,
          l10n.diagnosticsMissing,
          DiagnosticStatus.problem,
        )
      : DiagnosticRow(
          l10n.diagnosticsLabelPushKey,
          l10n.diagnosticsPresent,
          DiagnosticStatus.ok,
        ),
  _registration(l10n, inputs.currentPushkey, inputs.pushers, current),
  if (current != null)
    ..._fitRows(l10n, pusherFit(current, gatewayUrl: inputs.expectedGateway)),
];

List<DiagnosticRow> _fitRows(AppLocalizations l10n, PusherFit fit) => [
  _fitRow(l10n, l10n.diagnosticsLabelGateway, matches: fit.gateway),
  _fitRow(l10n, l10n.diagnosticsLabelFormat, matches: fit.format),
];

DiagnosticRow _fitRow(
  AppLocalizations l10n,
  String label, {
  required bool matches,
}) => matches
    ? DiagnosticRow(label, l10n.diagnosticsCorrect, DiagnosticStatus.ok)
    : DiagnosticRow(label, l10n.diagnosticsDifferent, DiagnosticStatus.problem);

DiagnosticRow _unknown(AppLocalizations l10n, String label) =>
    DiagnosticRow(label, l10n.diagnosticsUnknown, DiagnosticStatus.warning);

DiagnosticSection _androidPermission(
  AppLocalizations l10n,
  PushDiagnosticsInputs inputs,
) {
  final android = inputs.snapshot.android;
  final capabilities = inputs.capabilities;
  final channels = android.channels;
  final notifications = l10n.diagnosticsLabelNotifications;
  final fullScreen = l10n.diagnosticsLabelFullScreenCallAlerts;
  final battery = l10n.diagnosticsLabelBatteryUse;
  final backgroundData = l10n.diagnosticsLabelBackgroundData;
  return DiagnosticSection(l10n.diagnosticsSectionPermission, [
    switch (android.notificationsEnabled) {
      true => DiagnosticRow(
        notifications,
        l10n.diagnosticsAllowed,
        DiagnosticStatus.ok,
      ),
      false => DiagnosticRow(
        notifications,
        l10n.diagnosticsNotAllowed,
        DiagnosticStatus.problem,
      ),
      null => _unknown(l10n, notifications),
    },
    if (channels == null)
      _unknown(l10n, l10n.diagnosticsLabelNotificationCategories)
    else
      for (final channel in channels)
        _channelRow(
          l10n,
          channel,
          quiet: android.notificationsEnabled == false,
        ),
    if (capabilities.fullScreenIntent)
      switch (android.fullScreenIntent) {
        true => DiagnosticRow(
          fullScreen,
          l10n.diagnosticsAllowed,
          DiagnosticStatus.ok,
        ),
        false => DiagnosticRow(
          fullScreen,
          l10n.diagnosticsNotAllowed,
          DiagnosticStatus.warning,
        ),
        null => _unknown(l10n, fullScreen),
      },
    if (capabilities.batteryExemption)
      switch (android.batteryOptimizationIgnored) {
        true => DiagnosticRow(
          battery,
          l10n.diagnosticsBatteryUnrestricted,
          DiagnosticStatus.ok,
        ),
        false => DiagnosticRow(
          battery,
          l10n.diagnosticsBatteryOptimized,
          deliveryDependsOnBatteryExemption(inputs.deliveryMode)
              ? DiagnosticStatus.warning
              : DiagnosticStatus.info,
        ),
        null => _unknown(l10n, battery),
      },
    if (capabilities.backgroundDataRestriction)
      switch (android.backgroundData) {
        'allowed' => DiagnosticRow(
          backgroundData,
          l10n.diagnosticsAllowed,
          DiagnosticStatus.ok,
        ),
        'exempt' => DiagnosticRow(
          backgroundData,
          l10n.diagnosticsBackgroundDataExempt,
          DiagnosticStatus.ok,
        ),
        'restricted' => DiagnosticRow(
          backgroundData,
          l10n.diagnosticsBackgroundDataRestricted,
          DiagnosticStatus.warning,
        ),
        _ => _unknown(l10n, backgroundData),
      },
    _standby(
      l10n,
      inputs.deliveries?.firstOrNull?.standbyBucket,
      android.standbyBucket,
    ),
  ]);
}

DiagnosticRow _channelRow(
  AppLocalizations l10n,
  AndroidChannelState channel, {
  required bool quiet,
}) {
  final rings = ringChannelIds.contains(channel.id);
  final alerting = rings || alertingMessageChannelIds.contains(channel.id);
  final value = switch (channel.importance) {
    'none' => l10n.diagnosticsChannelBlocked,
    'min' => l10n.diagnosticsChannelSilentMinimized,
    'low' => l10n.diagnosticsChannelSilent,
    'default' => l10n.diagnosticsChannelSound,
    'high' || 'max' => l10n.diagnosticsChannelSoundPopUp,
    _ => l10n.diagnosticsUnknown,
  };
  final status = quiet || !alerting
      ? DiagnosticStatus.info
      : switch (channel.importance) {
          'none' => DiagnosticStatus.problem,
          'default' when rings => DiagnosticStatus.warning,
          'default' || 'high' || 'max' => DiagnosticStatus.ok,
          _ => DiagnosticStatus.warning,
        };
  return DiagnosticRow(channel.name, value, status);
}

DiagnosticRow _standby(AppLocalizations l10n, int? recorded, int? live) {
  final bucket = recorded ?? live;
  final measured = recorded != null;
  final label = l10n.diagnosticsLabelAppStandby;
  DiagnosticStatus level(DiagnosticStatus status) =>
      measured ? status : DiagnosticStatus.info;
  return switch (bucket) {
    5 => DiagnosticRow(
      label,
      l10n.diagnosticsStandbyExempt,
      level(DiagnosticStatus.ok),
    ),
    10 => DiagnosticRow(
      label,
      l10n.diagnosticsStandbyActive,
      level(DiagnosticStatus.ok),
    ),
    20 => DiagnosticRow(
      label,
      l10n.diagnosticsStandbyUsedOften,
      level(DiagnosticStatus.ok),
    ),
    30 => DiagnosticRow(label, l10n.diagnosticsStandbyUsedRegularly),
    40 => DiagnosticRow(
      label,
      l10n.diagnosticsStandbyUsedRarely,
      level(DiagnosticStatus.warning),
    ),
    45 => DiagnosticRow(
      label,
      l10n.diagnosticsStandbyRestricted,
      level(DiagnosticStatus.problem),
    ),
    50 => DiagnosticRow(
      label,
      l10n.diagnosticsStandbyNeverUsed,
      level(DiagnosticStatus.problem),
    ),
    _ => DiagnosticRow(label, l10n.diagnosticsUnknown),
  };
}

DiagnosticSection _androidDevice(
  AppLocalizations l10n,
  PushDiagnosticsInputs inputs,
) {
  final mode = inputs.deliveryMode;
  return DiagnosticSection(l10n.diagnosticsSectionDevice, [
    DiagnosticRow(l10n.diagnosticsLabelDelivery, mode.label(l10n)),
    ?_deliveryStatus(l10n, inputs),
    if (inputs.capabilities.deliveryModes.contains(
      NotificationDeliveryMode.fcm,
    ))
      _playServices(
        l10n,
        inputs.playServices,
        needed: mode == NotificationDeliveryMode.fcm,
      ),
    if (mode != NotificationDeliveryMode.backgroundService)
      ..._registrationRows(l10n, inputs, _currentPusher(inputs)),
    DiagnosticRow(l10n.diagnosticsLabelZunoVersion, inputs.appVersion),
  ]);
}

DiagnosticRow? _deliveryStatus(
  AppLocalizations l10n,
  PushDiagnosticsInputs inputs,
) => switch ((
  inputs.deliveryMode,
  inputs.fcmStatus,
  inputs.unifiedPushStatus,
)) {
  (NotificationDeliveryMode.fcm, final FcmStatus status, _) => DiagnosticRow(
    l10n.commonStatus,
    fcmStatusLabel(l10n, status),
    _fcmStatusLevel(status),
  ),
  (NotificationDeliveryMode.unifiedPush, _, final UnifiedPushStatus status) =>
    DiagnosticRow(
      l10n.commonStatus,
      unifiedPushStatusLabel(l10n, status),
      _unifiedPushStatusLevel(status),
    ),
  _ => null,
};

DiagnosticStatus _fcmStatusLevel(FcmStatus status) => switch (status) {
  FcmStatus.ready => DiagnosticStatus.ok,
  FcmStatus.idle => DiagnosticStatus.warning,
  FcmStatus.checkingPlayServices ||
  FcmStatus.registering ||
  FcmStatus.postingPusher => DiagnosticStatus.info,
  FcmStatus.playServicesUnavailable ||
  FcmStatus.playServicesUpdateRequired ||
  FcmStatus.playServicesDisabled ||
  FcmStatus.notConfigured ||
  FcmStatus.tokenFailed ||
  FcmStatus.pusherFailed => DiagnosticStatus.problem,
};

DiagnosticStatus _unifiedPushStatusLevel(UnifiedPushStatus status) =>
    switch (status) {
      UnifiedPushStatus.ready => DiagnosticStatus.ok,
      UnifiedPushStatus.idle ||
      UnifiedPushStatus.distributorSelected => DiagnosticStatus.warning,
      UnifiedPushStatus.findingDistributor ||
      UnifiedPushStatus.registering ||
      UnifiedPushStatus.postingPusher => DiagnosticStatus.info,
      UnifiedPushStatus.noDistributorFound ||
      UnifiedPushStatus.registrationFailed ||
      UnifiedPushStatus.pusherFailed => DiagnosticStatus.problem,
    };

DiagnosticRow _playServices(
  AppLocalizations l10n,
  FcmAvailability? availability, {
  required bool needed,
}) {
  final label = l10n.diagnosticsLabelGooglePlayServices;
  final missing = needed ? DiagnosticStatus.problem : DiagnosticStatus.info;
  return switch (availability) {
    FcmAvailability.available => DiagnosticRow(
      label,
      l10n.diagnosticsAvailable,
      DiagnosticStatus.ok,
    ),
    FcmAvailability.updateRequired => DiagnosticRow(
      label,
      l10n.diagnosticsPlayNeedsUpdate,
      DiagnosticStatus.warning,
    ),
    FcmAvailability.disabled => DiagnosticRow(
      label,
      l10n.diagnosticsTurnedOff,
      missing,
    ),
    FcmAvailability.unavailable => DiagnosticRow(
      label,
      l10n.diagnosticsPlayNotOnDevice,
      missing,
    ),
    FcmAvailability.notConfigured => DiagnosticRow(
      label,
      l10n.diagnosticsPlayNotIncluded,
      missing,
    ),
    FcmAvailability.unknown || null => DiagnosticRow(
      label,
      l10n.diagnosticsCouldNotCheck,
      DiagnosticStatus.warning,
    ),
  };
}

DiagnosticRow _registration(
  AppLocalizations l10n,
  String? pushkey,
  List<PusherInfo>? pushers,
  PusherInfo? current,
) {
  final label = l10n.diagnosticsLabelRegistration;
  if (pushkey == null) {
    return DiagnosticRow(
      label,
      l10n.diagnosticsRegistrationNotSetUp,
      DiagnosticStatus.problem,
    );
  }
  if (pushers == null) {
    return DiagnosticRow(
      label,
      l10n.diagnosticsCouldNotCheck,
      DiagnosticStatus.warning,
    );
  }
  if (current == null) {
    return DiagnosticRow(
      label,
      l10n.diagnosticsRegistrationNotRegistered,
      DiagnosticStatus.problem,
    );
  }
  return DiagnosticRow(
    label,
    l10n.diagnosticsRegistrationRegistered,
    DiagnosticStatus.ok,
  );
}

DiagnosticSection _calls(DateLabels labels, PushDiagnosticsInputs inputs) {
  final l10n = labels.l10n;
  final voip = inputs.voip;
  final health = inputs.health;
  final ledger = inputs.snapshot.ledger;
  final mismatches = ringMismatches(
    health: health,
    deviceKid: voip?.kid,
    deviceHasToken: voip?.hasToken ?? false,
    ledger: ledger,
  );
  bool found(RingMismatchKind kind) => mismatches.any((m) => m.kind == kind);
  DateTime? lastActivity;
  for (final call in ledger ?? const <LedgerCall>[]) {
    if (call.source != 'push') continue;
    if (lastActivity == null || call.at.isAfter(lastActivity)) {
      lastActivity = call.at;
    }
  }
  final callScreen = l10n.diagnosticsLabelSystemCallScreen;
  final callPushKey = l10n.diagnosticsLabelCallPushKey;
  final callKey = l10n.diagnosticsLabelCallKey;
  final lastActivityLabel = l10n.diagnosticsLabelLastCallActivity;
  return DiagnosticSection(l10n.diagnosticsSectionCalls, [
    switch (voip?.callKit) {
      true => DiagnosticRow(
        callScreen,
        l10n.diagnosticsAvailable,
        DiagnosticStatus.ok,
      ),
      false => DiagnosticRow(
        callScreen,
        l10n.diagnosticsNotAvailableHere,
        DiagnosticStatus.warning,
      ),
      null => _unknown(l10n, callScreen),
    },
    switch (voip?.hasToken) {
      true => DiagnosticRow(
        callPushKey,
        l10n.diagnosticsPresent,
        DiagnosticStatus.ok,
      ),
      false => DiagnosticRow(
        callPushKey,
        l10n.diagnosticsMissing,
        DiagnosticStatus.problem,
      ),
      null => _unknown(l10n, callPushKey),
    },
    if (health == null)
      DiagnosticRow(
        callKey,
        l10n.diagnosticsCouldNotCheck,
        DiagnosticStatus.warning,
      )
    else if (voip == null)
      _unknown(l10n, callKey)
    else if (found(RingMismatchKind.notRegistered))
      DiagnosticRow(
        callKey,
        l10n.diagnosticsRegistrationNotRegistered,
        DiagnosticStatus.problem,
      )
    else if (found(RingMismatchKind.keyDiffers))
      DiagnosticRow(
        callKey,
        l10n.diagnosticsCallKeyOutOfDate,
        DiagnosticStatus.warning,
      )
    else
      DiagnosticRow(
        callKey,
        l10n.diagnosticsCallKeyCurrent,
        DiagnosticStatus.ok,
      ),
    if (ledger == null)
      _unknown(l10n, lastActivityLabel)
    else
      DiagnosticRow(
        lastActivityLabel,
        lastActivity == null
            ? l10n.diagnosticsNoneYet
            : labels.age(lastActivity, inputs.now),
      ),
    _lastRingSent(labels, health, inputs.now),
    if (found(RingMismatchKind.lastRingNotReceived))
      DiagnosticRow(
        l10n.diagnosticsLabelLastRing,
        l10n.diagnosticsLastRingNotReceived,
        DiagnosticStatus.problem,
      ),
    if (inputs.voipRefusal case final refusal?)
      _callSetup(labels, refusal, inputs.now),
  ]);
}

DiagnosticRow _callSetup(DateLabels labels, VoipRefusal refusal, DateTime now) {
  final l10n = labels.l10n;
  final age = labels.age(refusal.at, now, inSentence: true);
  return DiagnosticRow(l10n.diagnosticsLabelCallSetup, switch (refusal) {
    VoipRefusedByServer(:final reply) => [
      l10n.diagnosticsCallSetupRefusedByServer(
        age,
        reply.status,
        reply.errcode,
      ),
      ?reply.error,
    ].join('\n'),
    VoipKeyNotKept() => l10n.diagnosticsCallSetupKeyNotKept(age),
  }, DiagnosticStatus.problem);
}

DiagnosticRow _lastRingSent(
  DateLabels labels,
  ServerHealth? health,
  DateTime now,
) {
  final l10n = labels.l10n;
  final label = l10n.diagnosticsLabelLastRingSent;
  if (health == null) {
    return DiagnosticRow(
      label,
      l10n.diagnosticsCouldNotCheck,
      DiagnosticStatus.warning,
    );
  }
  final at = health.voipLastAt;
  if (at == null) {
    return DiagnosticRow(label, l10n.diagnosticsNoneYet);
  }
  final sentAt = health.toDevice(at);
  final age = labels.age(sentAt, now, inSentence: true);
  return switch (health.voipLastResult) {
    'sent' => DiagnosticRow(
      label,
      l10n.diagnosticsSentAgo(age),
      DiagnosticStatus.ok,
    ),
    'failed' => DiagnosticRow(
      label,
      l10n.diagnosticsFailedAgo(age),
      DiagnosticStatus.problem,
    ),
    'rejected' => DiagnosticRow(
      label,
      l10n.diagnosticsRefusedAgo(age),
      DiagnosticStatus.problem,
    ),
    _ => DiagnosticRow(label, labels.age(sentAt, now)),
  };
}

DiagnosticSection _extension(DateLabels labels, PushDiagnosticsInputs inputs) {
  final l10n = labels.l10n;
  final snapshot = inputs.snapshot;
  final lastRun = snapshot.extensionLastRun;
  final version = snapshot.extensionVersion;
  final updated = snapshot.readModelUpdatedAt;
  final versionLabel = l10n.commonVersion;
  final updatedLabel = l10n.diagnosticsLabelSharedDataUpdated;
  return DiagnosticSection(l10n.diagnosticsSectionExtension, [
    lastRun == null
        ? DiagnosticRow(
            l10n.diagnosticsLabelLastRun,
            l10n.diagnosticsNever,
            DiagnosticStatus.warning,
          )
        : DiagnosticRow(
            l10n.diagnosticsLabelLastRun,
            labels.age(lastRun, inputs.now),
          ),
    if (version == null)
      DiagnosticRow(versionLabel, l10n.diagnosticsUnknown)
    else if (sameBuild(version, inputs.appVersion))
      DiagnosticRow(versionLabel, version, DiagnosticStatus.ok)
    else
      DiagnosticRow(
        versionLabel,
        l10n.diagnosticsExtensionVersionMismatch(version, inputs.appVersion),
        DiagnosticStatus.warning,
      ),
    updated == null
        ? DiagnosticRow(
            updatedLabel,
            l10n.diagnosticsNever,
            DiagnosticStatus.warning,
          )
        : DiagnosticRow(updatedLabel, labels.age(updated, inputs.now)),
    DiagnosticRow(
      l10n.diagnosticsLabelRecentResults,
      snapshot.extensionLog.isEmpty
          ? l10n.diagnosticsNoneYet
          : snapshot.extensionLog.join('\n'),
    ),
  ]);
}

DiagnosticSection _delivery(DateLabels labels, PushDiagnosticsInputs inputs) {
  final l10n = labels.l10n;
  final health = inputs.health;
  final reachable = l10n.diagnosticsLabelReachable;
  final unmetNeed =
      inputs.capabilities.voipRing || inputs.capabilities.nseNotifications
      ? DiagnosticStatus.problem
      : DiagnosticStatus.info;
  final rows = <DiagnosticRow>[
    switch (inputs.reach) {
      ServerReach.reachable => DiagnosticRow(
        reachable,
        l10n.diagnosticsYes,
        DiagnosticStatus.ok,
      ),
      ServerReach.starting => DiagnosticRow(
        reachable,
        l10n.diagnosticsReachStarting,
        DiagnosticStatus.warning,
      ),
      ServerReach.unreachable => DiagnosticRow(
        reachable,
        l10n.diagnosticsNo,
        DiagnosticStatus.problem,
      ),
      ServerReach.turnedOff => DiagnosticRow(
        reachable,
        l10n.diagnosticsTurnedOff,
        unmetNeed,
      ),
      ServerReach.notInstalled => DiagnosticRow(
        reachable,
        l10n.diagnosticsReachNotOnServer,
        unmetNeed,
      ),
    },
  ];
  if (health != null) {
    final appId = _currentPusher(inputs)?.appId;
    final pusher =
        health.pushers.where((p) => p.appId == appId).firstOrNull ??
        (inputs.capabilities.apnsRegistration
            ? health.pushers
                  .where((p) => p.appId.startsWith('im.zuno.chat.ios'))
                  .firstOrNull
            : null) ??
        health.pushers.firstOrNull;
    final lastSuccess = pusher?.lastSuccess;
    rows.add(
      DiagnosticRow(
        l10n.diagnosticsLabelLastDelivery,
        lastSuccess == null
            ? l10n.diagnosticsNoneYet
            : labels.age(health.toDevice(lastSuccess), inputs.now),
      ),
    );
    final failingSince = pusher?.failingSince;
    if (failingSince != null) {
      rows.add(
        DiagnosticRow(
          l10n.diagnosticsLabelFailingSince,
          labels.age(health.toDevice(failingSince), inputs.now),
          DiagnosticStatus.problem,
        ),
      );
    }
    if (inputs.capabilities.nseNotifications) {
      final access = l10n.diagnosticsLabelExtensionAccess;
      rows.add(switch (health.credentialExpires) {
        null => DiagnosticRow(
          access,
          l10n.diagnosticsNone,
          DiagnosticStatus.warning,
        ),
        final DateTime expires
            when health.toDevice(expires).isBefore(inputs.now) =>
          DiagnosticRow(
            access,
            l10n.diagnosticsExtensionAccessExpired,
            DiagnosticStatus.problem,
          ),
        _ => DiagnosticRow(
          access,
          l10n.diagnosticsExtensionAccessValid,
          DiagnosticStatus.ok,
        ),
      });
      final fetched = health.lastFetch;
      rows.add(
        DiagnosticRow(
          l10n.diagnosticsLabelExtensionCheckedIn,
          fetched == null
              ? l10n.diagnosticsNever
              : labels.age(health.toDevice(fetched), inputs.now),
        ),
      );
    }
  }
  if (inputs.deliveries case final deliveries?) {
    final last = deliveries.firstOrNull;
    final label = l10n.diagnosticsLabelLastPush;
    rows.add(
      last == null
          ? DiagnosticRow(label, l10n.diagnosticsNoneYet)
          : DiagnosticRow(
              label,
              l10n.diagnosticsLastPushSummary(
                pushDeliverySummary(l10n, last),
                labels.age(last.receivedAt, inputs.now),
              ),
              last.late ? DiagnosticStatus.warning : DiagnosticStatus.info,
            ),
    );
  }
  return DiagnosticSection(l10n.diagnosticsSectionDelivery, rows);
}

DiagnosticSection _reports(DateLabels labels, PushDiagnosticsInputs inputs) {
  final l10n = labels.l10n;
  return DiagnosticSection(l10n.diagnosticsSectionReports, [
    for (final report in inputs.snapshot.metrics)
      DiagnosticRow(
        _reportLabel(l10n, report.kind),
        l10n.diagnosticsReportEntry(
          _countsText(l10n, report.counts),
          labels.age(report.end, inputs.now),
        ),
        DiagnosticStatus.warning,
      ),
  ]);
}

String _countsText(AppLocalizations l10n, Map<String, int> counts) => [
  for (final MapEntry(:key, :value) in counts.entries)
    l10n.diagnosticsCountEntry(_countLabel(l10n, key), value),
].join(l10n.diagnosticsSeparator);
