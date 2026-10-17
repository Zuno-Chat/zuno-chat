import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'security_alert.dart';

const _prefix = 'security.alerts.';

class SecurityAlertStore {
  final SharedPreferences _prefs;

  SecurityAlertStore(this._prefs);

  List<RecordedSecurityAlert> open(String userId) {
    final raw = _prefs.getString('$_prefix$userId');
    if (raw == null) return const [];
    return [
      for (final entry in jsonDecode(raw) as List)
        ?_decode(entry as Map<String, Object?>),
    ];
  }

  Future<void> save(String userId, List<RecordedSecurityAlert> alerts) =>
      alerts.isEmpty
      ? _prefs.remove('$_prefix$userId')
      : _prefs.setString(
          '$_prefix$userId',
          jsonEncode([for (final alert in alerts) _encode(alert)]),
        );
}

Map<String, Object?> _encode(RecordedSecurityAlert alert) => switch (alert) {
  RecoveryResetAlert(:final identityKey) => {
    'kind': 'recoveryReset',
    'identityKey': identityKey,
  },
  NewSignInAlert(
    :final deviceId,
    :final displayName,
    :final ipAddress,
    :final seenAt,
  ) =>
    {
      'kind': 'newSignIn',
      'deviceId': deviceId,
      'displayName': ?displayName,
      'ipAddress': ?ipAddress,
      'seenAtMs': ?seenAt?.millisecondsSinceEpoch,
    },
  UnvouchedDeviceAlert(:final userId, :final deviceIds) => {
    'kind': 'unvouchedDevice',
    'userId': userId,
    'deviceIds': deviceIds.toList()..sort(),
  },
};

RecordedSecurityAlert? _decode(Map<String, Object?> json) =>
    switch (json['kind']) {
      'recoveryReset' => RecoveryResetAlert(json['identityKey']! as String),
      'newSignIn' => NewSignInAlert(
        deviceId: json['deviceId']! as String,
        displayName: json['displayName'] as String?,
        ipAddress: json['ipAddress'] as String?,
        seenAt: switch (json['seenAtMs']) {
          final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
          _ => null,
        },
      ),
      'unvouchedDevice' => UnvouchedDeviceAlert(
        userId: json['userId']! as String,
        deviceIds: (json['deviceIds']! as List).cast<String>().toSet(),
      ),
      _ => null,
    };
