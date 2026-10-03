import 'package:flutter/foundation.dart' show immutable, listEquals;

import '../errors/crash_scrubber.dart';
import '../platform/platform_capabilities.dart';
import 'apns_pusher.dart';
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
}

List<DiagnosticSection> buildPushDiagnostics(PushDiagnosticsInputs inputs) => [
  _permission(inputs.snapshot.settings),
  _device(inputs),
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
  final pushkey = inputs.currentPushkey;
  final pushers = inputs.pushers;
  final current = pushkey == null || pushers == null
      ? null
      : pushers.where((pusher) => pusher.pushkey == pushkey).firstOrNull;
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
    pushkey == null
        ? const DiagnosticRow('Push key', 'Missing', DiagnosticStatus.problem)
        : const DiagnosticRow('Push key', 'Present', DiagnosticStatus.ok),
    _registration(pushkey, pushers, current),
    if (current != null)
      inputs.expectedGateway == null ||
              Uri.tryParse(current.url ?? '') == inputs.expectedGateway
          ? const DiagnosticRow('Gateway', 'Correct', DiagnosticStatus.ok)
          : const DiagnosticRow(
              'Gateway',
              'Different',
              DiagnosticStatus.problem,
            ),
    if (current != null)
      current.format == apnsPusherFormat
          ? const DiagnosticRow('Format', 'Correct', DiagnosticStatus.ok)
          : const DiagnosticRow(
              'Format',
              'Different',
              DiagnosticStatus.problem,
            ),
    DiagnosticRow('Zuno version', inputs.appVersion),
  ]);
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
      ServerReach.turnedOff => const DiagnosticRow(
        'Reachable',
        'Turned off',
        DiagnosticStatus.problem,
      ),
    },
  ];
  if (health != null) {
    final pusher =
        health.pushers
            .where((p) => p.appId.startsWith('im.zuno.chat.ios'))
            .firstOrNull ??
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
