import 'package:flutter/foundation.dart';

Map<String, Object?> zunoPushObject(Object? value, String key) {
  if (value is Map<String, Object?>) return value;
  throw FormatException('$key is not an object');
}

int _int(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw FormatException('$key is not an integer');
}

int? _optionalInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null || value is int) return value as int?;
  throw FormatException('$key is not an integer');
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw FormatException('$key is not a string');
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null || value is String) return value as String?;
  throw FormatException('$key is not a string');
}

bool? _optionalBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null || value is bool) return value as bool?;
  throw FormatException('$key is not a boolean');
}

List<Map<String, Object?>> _objects(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List) throw FormatException('$key is not a list');
  return [for (final entry in value) zunoPushObject(entry, key)];
}

@immutable
class PusherHealth {
  const PusherHealth({
    required this.appId,
    required this.lastSuccessTs,
    required this.failingSinceTs,
  });

  factory PusherHealth.fromJson(Map<String, Object?> json) => PusherHealth(
    appId: _string(json, 'app_id'),
    lastSuccessTs: _optionalInt(json, 'last_success_ts'),
    failingSinceTs: _optionalInt(json, 'failing_since_ts'),
  );

  final String appId;
  final int? lastSuccessTs;
  final int? failingSinceTs;
}

enum VoipSendResult { sent, failed, rejected }

@immutable
class VoipHealth {
  const VoipHealth({
    required this.registered,
    required this.kid,
    required this.lastResult,
    required this.lastTs,
  });

  factory VoipHealth.fromJson(Map<String, Object?> json) {
    final result = _optionalString(json, 'last_result');
    return VoipHealth(
      registered: _optionalBool(json, 'registered') ?? false,
      kid: _optionalInt(json, 'kid'),
      lastResult: VoipSendResult.values.asNameMap()[result],
      lastTs: _optionalInt(json, 'last_ts'),
    );
  }

  final bool registered;
  final int? kid;
  final VoipSendResult? lastResult;
  final int? lastTs;
}

@immutable
class NseHealth {
  const NseHealth({
    required this.credentialExpiresTs,
    required this.lastFetchTs,
  });

  factory NseHealth.fromJson(Map<String, Object?> json) => NseHealth(
    credentialExpiresTs: _optionalInt(json, 'credential_expires_ts'),
    lastFetchTs: _optionalInt(json, 'last_fetch_ts'),
  );

  final int? credentialExpiresTs;
  final int? lastFetchTs;
}

@immutable
class PushHealth {
  const PushHealth({
    required this.pushers,
    required this.voip,
    required this.nse,
  });

  factory PushHealth.fromJson(Map<String, Object?> json) => PushHealth(
    pushers: [
      for (final pusher in _objects(json, 'pushers'))
        PusherHealth.fromJson(pusher),
    ],
    voip: VoipHealth.fromJson(zunoPushObject(json['voip'], 'voip')),
    nse: NseHealth.fromJson(zunoPushObject(json['nse'], 'nse')),
  );

  final List<PusherHealth> pushers;
  final VoipHealth voip;
  final NseHealth nse;
}

final _credential = RegExp(r'^[A-Za-z0-9_-]{43}$');

@immutable
class NseCredentialGrant {
  const NseCredentialGrant({required this.credential, required this.expiresTs});

  factory NseCredentialGrant.fromJson(Map<String, Object?> json) {
    final credential = _string(json, 'credential');
    if (!_credential.hasMatch(credential)) {
      throw const FormatException('credential is not 43 base64url characters');
    }
    return NseCredentialGrant(
      credential: credential,
      expiresTs: _int(json, 'expires_ts'),
    );
  }

  final String credential;
  final int expiresTs;
}
