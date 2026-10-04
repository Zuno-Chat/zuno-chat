import 'package:flutter/foundation.dart' show immutable, listEquals;

import '../../features/settings/presentation/fcm_status_display.dart'
    show fcmStatusLabel;
import '../../features/settings/presentation/unified_push_status_display.dart'
    show unifiedPushStatusLabel;
import '../calls/notifications/call_notification_service.dart'
    show alertingMessageChannelIds, ringChannelIds;
import '../errors/crash_scrubber.dart';
import '../notifications/fcm_delivery_provider.dart' show FcmStatus;
import '../notifications/notification_delivery_mode.dart';
import '../notifications/unified_push_delivery_provider.dart'
    show UnifiedPushStatus;
import '../platform/platform_capabilities.dart';
import 'apns_pusher.dart';
import 'fcm_bridge.dart' show FcmAvailability;
import 'push_delivery_log.dart';
import 'push_diagnostics_data.dart';
import 'pusher_info.dart';
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
}

List<DiagnosticSection> buildPushDiagnostics(PushDiagnosticsInputs inputs) => [
  if (inputs.capabilities.apnsRegistration) ...[
    _permission(inputs.snapshot.settings),
    _device(inputs),
  ] else ...[
    _androidPermission(inputs),
    _androidDevice(inputs),
  ],
  if (inputs.capabilities.voipRing) _calls(inputs),
  if (inputs.capabilities.nseNotifications) _extension(inputs),
  _delivery(inputs),
  if (inputs.snapshot.metrics.isNotEmpty) _reports(inputs),
];

String ageLabel(DateTime at, DateTime now) {
  final age = now.difference(at);
  if (age < const Duration(minutes: 1)) return 'Just now';
  if (age < const Duration(hours: 1)) return '${age.inMinutes} min ago';
  if (age < const Duration(days: 1)) return '${age.inHours} h ago';
  final days = age.inDays;
  return days == 1 ? '1 day ago' : '$days days ago';
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
  List<DiagnosticSection> sections, {
  required DateTime now,
  required String appVersion,
}) {
  final buffer = StringBuffer()
    ..writeln('Zuno notification diagnostics')
    ..writeln('Zuno $appVersion, ${now.toUtc().toIso8601String()}');
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

const _settingLabels = {
  'authorization': 'Notifications',
  'alert': 'Alerts',
  'alertStyle': 'Banner style',
  'sound': 'Sounds',
  'badge': 'Badges',
  'lockScreen': 'Lock screen',
  'notificationCenter': 'Notification Center',
  'showPreviews': 'Show previews',
  'timeSensitive': 'Time Sensitive notifications',
  'scheduledDelivery': 'Scheduled summary',
  'directMessages': 'Direct messages',
  'announcement': 'Announce notifications',
  'carPlay': 'CarPlay',
  'criticalAlert': 'Critical alerts',
  'providesAppSettings': 'Link from iOS Settings',
};

const _settingValues = {
  'authorized': 'Allowed',
  'denied': 'Not allowed',
  'notDetermined': 'Not asked yet',
  'provisional': 'Delivered quietly',
  'ephemeral': 'Allowed for now',
  'enabled': 'On',
  'disabled': 'Off',
  'notSupported': 'Not available',
  'unknown': 'Unknown',
  'none': 'None',
  'banner': 'Temporary',
  'alert': 'Persistent',
  'always': 'Always',
  'whenAuthenticated': 'When unlocked',
  'never': 'Never',
  'true': 'Yes',
  'false': 'No',
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

const _reportLabels = {
  'exits': 'Background exits',
  'crash': 'Crashes',
  'memory': 'Memory limits',
};

const _countLabels = {
  'locked_file': 'Held a file while suspended',
  'memory': 'Out of memory',
  'watchdog': 'Took too long',
  'task_timeout': 'Background time ran out',
  'cpu': 'Used too much processing time',
  'bad_access': 'Crashed',
  'abnormal': 'Ended unexpectedly',
  'pushkit_unreported': 'Call not shown in time',
  'extension_memory': 'Notification extension out of memory',
};

DiagnosticSection _permission(Map<String, String> settings) {
  if (settings.isEmpty) {
    return const DiagnosticSection('Permission', [
      DiagnosticRow(
        'Settings',
        'Not available on this device',
        DiagnosticStatus.warning,
      ),
    ]);
  }
  final keys = [
    ..._settingOrder.where(settings.containsKey),
    ...settings.keys.where((key) => !_settingOrder.contains(key)),
  ];
  return DiagnosticSection('Permission', [
    for (final key in keys)
      DiagnosticRow(
        _settingLabels[key] ?? key,
        _settingValues[settings[key]] ?? settings[key]!,
        _settingStatus(key, settings[key]!),
      ),
  ]);
}

DiagnosticSection _device(PushDiagnosticsInputs inputs) {
  final environment = inputs.voip?.environment ?? inputs.snapshot.environment;
  final expectedAppId = switch (environment) {
    'production' => apnsProductionAppId,
    'development' => apnsDevelopmentAppId,
    _ => null,
  };
  final current = _currentPusher(inputs);
  final registeredAppId = current?.appId;
  return DiagnosticSection('This device', [
    DiagnosticRow('Environment', switch (environment) {
      'production' => 'Production',
      'development' => 'Development',
      _ => 'Unknown',
    }, environment == null ? DiagnosticStatus.warning : DiagnosticStatus.info),
    if (expectedAppId != null)
      registeredAppId == null || registeredAppId == expectedAppId
          ? DiagnosticRow('App ID', expectedAppId)
          : DiagnosticRow(
              'App ID',
              '$registeredAppId, expected $expectedAppId',
              DiagnosticStatus.problem,
            ),
    ..._registrationRows(inputs, current),
    if (inputs.snapshot.registeredForRemoteNotifications case final token?)
      token
          ? const DiagnosticRow('Device token', 'Received', DiagnosticStatus.ok)
          : const DiagnosticRow(
              'Device token',
              'Not received',
              DiagnosticStatus.problem,
            ),
    if (inputs.droppedRegistrations case final dropped?)
      DiagnosticRow(
        'Dropped registrations',
        '$dropped',
        dropped > 0 ? DiagnosticStatus.warning : DiagnosticStatus.info,
      ),
    DiagnosticRow('Zuno version', inputs.appVersion),
  ]);
}

PusherInfo? _currentPusher(PushDiagnosticsInputs inputs) {
  final pushkey = inputs.currentPushkey;
  final pushers = inputs.pushers;
  if (pushkey == null || pushers == null) return null;
  return pushers.where((pusher) => pusher.pushkey == pushkey).firstOrNull;
}

List<DiagnosticRow> _registrationRows(
  PushDiagnosticsInputs inputs,
  PusherInfo? current,
) => [
  inputs.currentPushkey == null
      ? const DiagnosticRow('Push key', 'Missing', DiagnosticStatus.problem)
      : const DiagnosticRow('Push key', 'Present', DiagnosticStatus.ok),
  _registration(inputs.currentPushkey, inputs.pushers, current),
  if (current != null)
    inputs.expectedGateway == null ||
            Uri.tryParse(current.url ?? '') == inputs.expectedGateway
        ? const DiagnosticRow('Gateway', 'Correct', DiagnosticStatus.ok)
        : const DiagnosticRow('Gateway', 'Different', DiagnosticStatus.problem),
  if (current != null)
    current.format == apnsPusherFormat
        ? const DiagnosticRow('Format', 'Correct', DiagnosticStatus.ok)
        : const DiagnosticRow('Format', 'Different', DiagnosticStatus.problem),
];

DiagnosticRow _unknown(String label) =>
    DiagnosticRow(label, 'Unknown', DiagnosticStatus.warning);

DiagnosticSection _androidPermission(PushDiagnosticsInputs inputs) {
  final android = inputs.snapshot.android;
  final capabilities = inputs.capabilities;
  final channels = android.channels;
  return DiagnosticSection('Permission', [
    switch (android.notificationsEnabled) {
      true => const DiagnosticRow(
        'Notifications',
        'Allowed',
        DiagnosticStatus.ok,
      ),
      false => const DiagnosticRow(
        'Notifications',
        'Not allowed',
        DiagnosticStatus.problem,
      ),
      null => _unknown('Notifications'),
    },
    if (channels == null)
      _unknown('Notification categories')
    else
      for (final channel in channels)
        _channelRow(channel, quiet: android.notificationsEnabled == false),
    if (capabilities.fullScreenIntent)
      switch (android.fullScreenIntent) {
        true => const DiagnosticRow(
          'Full-screen call alerts',
          'Allowed',
          DiagnosticStatus.ok,
        ),
        false => const DiagnosticRow(
          'Full-screen call alerts',
          'Not allowed',
          DiagnosticStatus.warning,
        ),
        null => _unknown('Full-screen call alerts'),
      },
    if (capabilities.batteryExemption)
      switch (android.batteryOptimizationIgnored) {
        true => const DiagnosticRow(
          'Battery use',
          'Unrestricted',
          DiagnosticStatus.ok,
        ),
        false => DiagnosticRow(
          'Battery use',
          'Optimized',
          deliveryDependsOnBatteryExemption(inputs.deliveryMode)
              ? DiagnosticStatus.warning
              : DiagnosticStatus.info,
        ),
        null => _unknown('Battery use'),
      },
    if (capabilities.backgroundDataRestriction)
      switch (android.backgroundData) {
        'allowed' => const DiagnosticRow(
          'Background data',
          'Allowed',
          DiagnosticStatus.ok,
        ),
        'exempt' => const DiagnosticRow(
          'Background data',
          'Allowed while Data Saver is on',
          DiagnosticStatus.ok,
        ),
        'restricted' => const DiagnosticRow(
          'Background data',
          'Restricted by Data Saver',
          DiagnosticStatus.warning,
        ),
        _ => _unknown('Background data'),
      },
    _standby(
      inputs.deliveries?.firstOrNull?.standbyBucket,
      android.standbyBucket,
    ),
  ]);
}

DiagnosticRow _channelRow(AndroidChannelState channel, {required bool quiet}) {
  final rings = ringChannelIds.contains(channel.id);
  final alerting = rings || alertingMessageChannelIds.contains(channel.id);
  final value = switch (channel.importance) {
    'none' => 'Blocked',
    'min' => 'Silent and minimized',
    'low' => 'Silent',
    'default' => 'Sound',
    'high' || 'max' => 'Sound and pop-up',
    _ => 'Unknown',
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

DiagnosticRow _standby(int? recorded, int? live) {
  final bucket = recorded ?? live;
  final measured = recorded != null;
  DiagnosticStatus level(DiagnosticStatus status) =>
      measured ? status : DiagnosticStatus.info;
  return switch (bucket) {
    5 => DiagnosticRow('App standby', 'Exempt', level(DiagnosticStatus.ok)),
    10 => DiagnosticRow('App standby', 'Active', level(DiagnosticStatus.ok)),
    20 => DiagnosticRow(
      'App standby',
      'Used often',
      level(DiagnosticStatus.ok),
    ),
    30 => const DiagnosticRow('App standby', 'Used regularly'),
    40 => DiagnosticRow(
      'App standby',
      'Used rarely',
      level(DiagnosticStatus.warning),
    ),
    45 => DiagnosticRow(
      'App standby',
      'Restricted',
      level(DiagnosticStatus.problem),
    ),
    50 => DiagnosticRow(
      'App standby',
      'Never used',
      level(DiagnosticStatus.problem),
    ),
    _ => const DiagnosticRow('App standby', 'Unknown'),
  };
}

DiagnosticSection _androidDevice(PushDiagnosticsInputs inputs) {
  final mode = inputs.deliveryMode;
  return DiagnosticSection('This device', [
    DiagnosticRow('Delivery', mode.label),
    ?_deliveryStatus(inputs),
    if (inputs.capabilities.deliveryModes.contains(
      NotificationDeliveryMode.fcm,
    ))
      _playServices(
        inputs.playServices,
        needed: mode == NotificationDeliveryMode.fcm,
      ),
    if (mode != NotificationDeliveryMode.backgroundService)
      ..._registrationRows(inputs, _currentPusher(inputs)),
    DiagnosticRow('Zuno version', inputs.appVersion),
  ]);
}

DiagnosticRow? _deliveryStatus(PushDiagnosticsInputs inputs) => switch ((
  inputs.deliveryMode,
  inputs.fcmStatus,
  inputs.unifiedPushStatus,
)) {
  (NotificationDeliveryMode.fcm, final FcmStatus status, _) => DiagnosticRow(
    'Status',
    fcmStatusLabel(status),
    _fcmStatusLevel(status),
  ),
  (NotificationDeliveryMode.unifiedPush, _, final UnifiedPushStatus status) =>
    DiagnosticRow(
      'Status',
      unifiedPushStatusLabel(status),
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
  FcmAvailability? availability, {
  required bool needed,
}) {
  const label = 'Google Play services';
  final missing = needed ? DiagnosticStatus.problem : DiagnosticStatus.info;
  return switch (availability) {
    FcmAvailability.available => const DiagnosticRow(
      label,
      'Available',
      DiagnosticStatus.ok,
    ),
    FcmAvailability.updateRequired => const DiagnosticRow(
      label,
      'Needs an update',
      DiagnosticStatus.warning,
    ),
    FcmAvailability.disabled => DiagnosticRow(label, 'Turned off', missing),
    FcmAvailability.unavailable => DiagnosticRow(
      label,
      'Not on this device',
      missing,
    ),
    FcmAvailability.notConfigured => DiagnosticRow(
      label,
      'Not included in this version of Zuno',
      missing,
    ),
    FcmAvailability.unknown || null => const DiagnosticRow(
      label,
      'Could not check',
      DiagnosticStatus.warning,
    ),
  };
}

DiagnosticRow _registration(
  String? pushkey,
  List<PusherInfo>? pushers,
  PusherInfo? current,
) {
  if (pushkey == null) {
    return const DiagnosticRow(
      'Registration',
      'Not set up',
      DiagnosticStatus.problem,
    );
  }
  if (pushers == null) {
    return const DiagnosticRow(
      'Registration',
      'Could not check',
      DiagnosticStatus.warning,
    );
  }
  if (current == null) {
    return const DiagnosticRow(
      'Registration',
      'Not registered',
      DiagnosticStatus.problem,
    );
  }
  return const DiagnosticRow('Registration', 'Registered', DiagnosticStatus.ok);
}

DiagnosticSection _calls(PushDiagnosticsInputs inputs) {
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
  return DiagnosticSection('Calls', [
    switch (voip?.callKit) {
      true => const DiagnosticRow(
        'System call screen',
        'Available',
        DiagnosticStatus.ok,
      ),
      false => const DiagnosticRow(
        'System call screen',
        'Not available here',
        DiagnosticStatus.warning,
      ),
      null => const DiagnosticRow(
        'System call screen',
        'Unknown',
        DiagnosticStatus.warning,
      ),
    },
    switch (voip?.hasToken) {
      true => const DiagnosticRow(
        'Call push key',
        'Present',
        DiagnosticStatus.ok,
      ),
      false => const DiagnosticRow(
        'Call push key',
        'Missing',
        DiagnosticStatus.problem,
      ),
      null => const DiagnosticRow(
        'Call push key',
        'Unknown',
        DiagnosticStatus.warning,
      ),
    },
    if (health == null)
      const DiagnosticRow(
        'Call key',
        'Could not check',
        DiagnosticStatus.warning,
      )
    else if (voip == null)
      const DiagnosticRow('Call key', 'Unknown', DiagnosticStatus.warning)
    else if (found(RingMismatchKind.notRegistered))
      const DiagnosticRow(
        'Call key',
        'Not registered',
        DiagnosticStatus.problem,
      )
    else if (found(RingMismatchKind.keyDiffers))
      const DiagnosticRow('Call key', 'Out of date', DiagnosticStatus.warning)
    else
      const DiagnosticRow('Call key', 'Current', DiagnosticStatus.ok),
    if (ledger == null)
      const DiagnosticRow(
        'Last call activity',
        'Unknown',
        DiagnosticStatus.warning,
      )
    else
      DiagnosticRow(
        'Last call activity',
        lastActivity == null ? 'None yet' : ageLabel(lastActivity, inputs.now),
      ),
    _lastRingSent(health, inputs.now),
    if (found(RingMismatchKind.lastRingNotReceived))
      const DiagnosticRow(
        'Last ring',
        'Sent but not received on this device',
        DiagnosticStatus.problem,
      ),
  ]);
}

DiagnosticRow _lastRingSent(ServerHealth? health, DateTime now) {
  if (health == null) {
    return const DiagnosticRow(
      'Last ring sent',
      'Could not check',
      DiagnosticStatus.warning,
    );
  }
  final at = health.voipLastAt;
  if (at == null) {
    return const DiagnosticRow('Last ring sent', 'None yet');
  }
  final age = ageLabel(health.toDevice(at), now);
  return switch (health.voipLastResult) {
    'sent' => DiagnosticRow('Last ring sent', 'Sent $age', DiagnosticStatus.ok),
    'failed' => DiagnosticRow(
      'Last ring sent',
      'Failed $age',
      DiagnosticStatus.problem,
    ),
    'rejected' => DiagnosticRow(
      'Last ring sent',
      'Refused $age',
      DiagnosticStatus.problem,
    ),
    _ => DiagnosticRow('Last ring sent', age),
  };
}

DiagnosticSection _extension(PushDiagnosticsInputs inputs) {
  final snapshot = inputs.snapshot;
  final lastRun = snapshot.extensionLastRun;
  final version = snapshot.extensionVersion;
  final updated = snapshot.readModelUpdatedAt;
  return DiagnosticSection('Notification extension', [
    lastRun == null
        ? const DiagnosticRow('Last run', 'Never', DiagnosticStatus.warning)
        : DiagnosticRow('Last run', ageLabel(lastRun, inputs.now)),
    if (version == null)
      const DiagnosticRow('Version', 'Unknown')
    else if (sameBuild(version, inputs.appVersion))
      DiagnosticRow('Version', version, DiagnosticStatus.ok)
    else
      DiagnosticRow(
        'Version',
        '$version. Zuno is ${inputs.appVersion}. Restart this device if this '
            'does not change after the next notification.',
        DiagnosticStatus.warning,
      ),
    updated == null
        ? const DiagnosticRow(
            'Shared data updated',
            'Never',
            DiagnosticStatus.warning,
          )
        : DiagnosticRow('Shared data updated', ageLabel(updated, inputs.now)),
    DiagnosticRow(
      'Recent results',
      snapshot.extensionLog.isEmpty
          ? 'None yet'
          : snapshot.extensionLog.join('\n'),
    ),
  ]);
}

DiagnosticSection _delivery(PushDiagnosticsInputs inputs) {
  final health = inputs.health;
  final rows = <DiagnosticRow>[
    switch (inputs.reach) {
      ServerReach.reachable => const DiagnosticRow(
        'Reachable',
        'Yes',
        DiagnosticStatus.ok,
      ),
      ServerReach.starting => const DiagnosticRow(
        'Reachable',
        'Starting',
        DiagnosticStatus.warning,
      ),
      ServerReach.unreachable => const DiagnosticRow(
        'Reachable',
        'No',
        DiagnosticStatus.problem,
      ),
      ServerReach.turnedOff => DiagnosticRow(
        'Reachable',
        'Turned off',
        inputs.capabilities.voipRing || inputs.capabilities.nseNotifications
            ? DiagnosticStatus.problem
            : DiagnosticStatus.info,
      ),
      ServerReach.notInstalled => DiagnosticRow(
        'Reachable',
        'Not available on this server',
        inputs.capabilities.voipRing || inputs.capabilities.nseNotifications
            ? DiagnosticStatus.problem
            : DiagnosticStatus.info,
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
        'Last delivery',
        lastSuccess == null
            ? 'None yet'
            : ageLabel(health.toDevice(lastSuccess), inputs.now),
      ),
    );
    final failingSince = pusher?.failingSince;
    if (failingSince != null) {
      rows.add(
        DiagnosticRow(
          'Failing since',
          ageLabel(health.toDevice(failingSince), inputs.now),
          DiagnosticStatus.problem,
        ),
      );
    }
    if (inputs.capabilities.nseNotifications) {
      rows.add(switch (health.credentialExpires) {
        null => const DiagnosticRow(
          'Extension access',
          'None',
          DiagnosticStatus.warning,
        ),
        final DateTime expires
            when health.toDevice(expires).isBefore(inputs.now) =>
          const DiagnosticRow(
            'Extension access',
            'Expired',
            DiagnosticStatus.problem,
          ),
        _ => const DiagnosticRow(
          'Extension access',
          'Valid',
          DiagnosticStatus.ok,
        ),
      });
      final fetched = health.lastFetch;
      rows.add(
        DiagnosticRow(
          'Extension last checked in',
          fetched == null
              ? 'Never'
              : ageLabel(health.toDevice(fetched), inputs.now),
        ),
      );
    }
  }
  if (inputs.deliveries case final deliveries?) {
    final last = deliveries.firstOrNull;
    rows.add(
      last == null
          ? const DiagnosticRow('Last push', 'None yet')
          : DiagnosticRow(
              'Last push',
              '${pushDeliverySummary(last)} (${ageLabel(last.receivedAt, inputs.now)})',
              last.late ? DiagnosticStatus.warning : DiagnosticStatus.info,
            ),
    );
  }
  return DiagnosticSection('Delivery', rows);
}

DiagnosticSection _reports(PushDiagnosticsInputs inputs) =>
    DiagnosticSection('Device reports', [
      for (final report in inputs.snapshot.metrics)
        DiagnosticRow(
          _reportLabels[report.kind] ?? report.kind,
          '${_countsText(report.counts)} (${ageLabel(report.end, inputs.now)})',
          DiagnosticStatus.warning,
        ),
    ]);

String _countsText(Map<String, int> counts) => [
  for (final MapEntry(:key, :value) in counts.entries)
    '${_countLabels[key] ?? key}: $value',
].join(', ');
