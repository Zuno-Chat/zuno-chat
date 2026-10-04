import 'package:flutter/foundation.dart' show immutable;

@immutable
class LedgerCall {
  const LedgerCall({
    required this.state,
    required this.source,
    required this.at,
  });

  final String state;
  final String source;
  final DateTime at;
}

@immutable
class MetricReport {
  const MetricReport({
    required this.kind,
    required this.counts,
    required this.end,
  });

  final String kind;
  final Map<String, int> counts;
  final DateTime end;
}

@immutable
class AndroidChannelState {
  const AndroidChannelState({
    required this.id,
    required this.name,
    required this.importance,
  });

  final String id;
  final String name;
  final String importance;
}

@immutable
class AndroidPushSnapshot {
  const AndroidPushSnapshot({
    this.notificationsEnabled,
    this.channels,
    this.fullScreenIntent,
    this.batteryOptimizationIgnored,
    this.backgroundData,
    this.standbyBucket,
  });

  static const empty = AndroidPushSnapshot();

  factory AndroidPushSnapshot.fromChannel(Map<Object?, Object?> raw) {
    final channels = raw['channels'];
    return AndroidPushSnapshot(
      notificationsEnabled: _flag(raw['notificationsEnabled']),
      channels: channels is List
          ? [for (final entry in channels) ?_channel(entry)]
          : null,
      fullScreenIntent: _flag(raw['fullScreenIntent']),
      batteryOptimizationIgnored: _flag(raw['batteryOptimizationIgnored']),
      backgroundData: _text(raw['backgroundData']),
      standbyBucket: switch (raw['standbyBucket']) {
        final int bucket => bucket,
        _ => null,
      },
    );
  }

  final bool? notificationsEnabled;
  final List<AndroidChannelState>? channels;
  final bool? fullScreenIntent;
  final bool? batteryOptimizationIgnored;
  final String? backgroundData;
  final int? standbyBucket;
}

@immutable
class PushDiagnosticsSnapshot {
  const PushDiagnosticsSnapshot({
    this.settings = const {},
    this.environment,
    this.ledger,
    this.readModelUpdatedAt,
    this.extensionLastRun,
    this.extensionVersion,
    this.extensionLog = const [],
    this.metrics = const [],
    this.appLog = const [],
    this.android = AndroidPushSnapshot.empty,
    this.registeredForRemoteNotifications,
  });

  static const empty = PushDiagnosticsSnapshot();

  factory PushDiagnosticsSnapshot.fromChannel(Object? raw) {
    if (raw is! Map) return empty;
    final settings = raw['settings'];
    final ledger = raw['ledger'];
    final nse = raw['nse'];
    final readModel = raw['read_model'];
    final app = raw['app'];
    return PushDiagnosticsSnapshot(
      settings: {
        if (settings is Map)
          for (final MapEntry(:key, :value) in settings.entries)
            if (key is String &&
                (value is String || value is num || value is bool))
              key: '$value',
      },
      environment: _text(raw['environment']),
      ledger: ledger is List
          ? [for (final entry in ledger) ?_ledgerCall(entry)]
          : null,
      readModelUpdatedAt: readModel is Map
          ? _time(readModel['updated_ms'])
          : null,
      extensionLastRun: nse is Map ? _time(nse['last_run_ms']) : null,
      extensionVersion: nse is Map ? _text(nse['version']) : null,
      extensionLog: [
        if (nse is Map)
          for (final line in _list(nse['log']))
            if (line is String) line,
      ],
      metrics: [for (final entry in _list(raw['metrics'])) ?_metric(entry)],
      appLog: [
        if (app is Map)
          for (final line in _list(app['log']))
            if (line is String) line,
      ],
      android: AndroidPushSnapshot.fromChannel(raw),
      registeredForRemoteNotifications: _flag(
        raw['registeredForRemoteNotifications'],
      ),
    );
  }

  final Map<String, String> settings;
  final String? environment;
  final List<LedgerCall>? ledger;
  final DateTime? readModelUpdatedAt;
  final DateTime? extensionLastRun;
  final String? extensionVersion;
  final List<String> extensionLog;
  final List<MetricReport> metrics;
  final List<String> appLog;
  final AndroidPushSnapshot android;
  final bool? registeredForRemoteNotifications;
}

@immutable
class VoipDeviceStatus {
  const VoipDeviceStatus({
    required this.hasToken,
    required this.callKit,
    this.environment,
    this.kid,
  });

  final bool hasToken;
  final bool callKit;
  final String? environment;
  final int? kid;
}

enum ServerReach { reachable, starting, unreachable, turnedOff, notInstalled }

@immutable
class PusherHealth {
  const PusherHealth({
    required this.appId,
    this.lastSuccess,
    this.failingSince,
  });

  final String appId;
  final DateTime? lastSuccess;
  final DateTime? failingSince;
}

@immutable
class ServerHealth {
  const ServerHealth({
    this.pushers = const [],
    required this.voipRegistered,
    this.voipKid,
    this.voipLastResult,
    this.voipLastAt,
    this.credentialExpires,
    this.lastFetch,
    this.serverOffset = Duration.zero,
  });

  final List<PusherHealth> pushers;
  final bool voipRegistered;
  final int? voipKid;
  final String? voipLastResult;
  final DateTime? voipLastAt;
  final DateTime? credentialExpires;
  final DateTime? lastFetch;
  final Duration serverOffset;

  DateTime toDevice(DateTime serverTime) => serverTime.subtract(serverOffset);
}

LedgerCall? _ledgerCall(Object? entry) {
  if (entry is! Map) return null;
  final state = entry['state'];
  final source = entry['source'];
  final at = _time(entry['ts']);
  if (state is! String || source is! String || at == null) return null;
  return LedgerCall(state: state, source: source, at: at);
}

MetricReport? _metric(Object? entry) {
  if (entry is! Map) return null;
  final kind = entry['kind'];
  final end = _time(entry['end_ms']);
  final counts = entry['counts'];
  if (kind is! String || end == null || counts is! Map) return null;
  return MetricReport(
    kind: kind,
    end: end,
    counts: {
      for (final MapEntry(:key, :value) in counts.entries)
        if (key is String && value is int && value > 0) key: value,
    },
  );
}

List<Object?> _list(Object? value) => value is List ? value : const [];

String? _text(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

DateTime? _time(Object? milliseconds) => milliseconds is int && milliseconds > 0
    ? DateTime.fromMillisecondsSinceEpoch(milliseconds)
    : null;

bool? _flag(Object? value) => value is bool ? value : null;

AndroidChannelState? _channel(Object? entry) {
  if (entry is! Map) return null;
  final id = entry['id'];
  final name = entry['name'];
  final importance = entry['importance'];
  if (id is! String || name is! String || importance is! String) return null;
  return AndroidChannelState(id: id, name: name, importance: importance);
}
