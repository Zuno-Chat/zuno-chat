import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import '../errors/retry_backoff.dart';
import '../security/secret_store.dart';
import 'bearer_authorization.dart';
import 'gateway_origin.dart';

typedef GatewayAuthorizationProvider = Future<String> Function({bool refresh});

class GatewayEnrollmentException implements Exception {
  final String message;
  final int? statusCode;

  GatewayEnrollmentException(this.message, {this.statusCode});

  @override
  String toString() => 'GatewayEnrollmentException: $message';
}

String gatewayTokenStorageKey({
  required String userId,
  required String deviceId,
}) => 'calls_gateway_token:$userId:$deviceId';

Uri gatewayEnrollUri(Client client) {
  final uri = gatewayOrigin(client, const ['calls', 'enroll']);
  if (uri == null) {
    throw StateError(
      'No homeserver set — the gateway is derived from it. '
      'checkHomeserver()/login must have run first.',
    );
  }
  return uri;
}

typedef _StoredToken = ({String token, DateTime expiresAt});

class GatewayCredentials {
  final Client client;
  final SecretStore _store;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final DateTime Function() _now;
  Future<String>? _inFlight;
  Future<_StoredToken>? _enrolling;
  _StoredToken? _cached;

  static const _expiryMargin = Duration(minutes: 1);

  GatewayCredentials({
    required this.client,
    this._store = const SecureSecretStore(),
    http.Client? httpClient,
    DateTime Function()? now,
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null,
       _now = now ?? DateTime.now;

  String get _storageKey {
    final userId = client.userID;
    final deviceId = client.deviceID;
    if (userId == null || deviceId == null) {
      throw StateError(
        'Not logged in — no user/device for gateway credentials.',
      );
    }
    return gatewayTokenStorageKey(userId: userId, deviceId: deviceId);
  }

  Future<String> authorization({bool refresh = false}) async =>
      'Bearer ${await token(refresh: refresh)}';

  Future<String> token({bool refresh = false}) {
    if (refresh) return _obtain(refresh: true);
    return _inFlight ??= _obtain(refresh: false)
        .whenComplete(() => _inFlight = null);
  }

  Future<String> _obtain({required bool refresh}) async {
    final key = _storageKey;
    if (!refresh) {
      var known = _cached ?? await _readStored(key);
      known = _cached ?? known;
      if (_enrolling == null && known != null && _isFresh(known.expiresAt)) {
        _cached = known;
        return known.token;
      }
    }
    final fresh = await (_enrolling ??= _enroll()
        .then((fresh) async {
          _cached = fresh;
          await _writeStored(key, fresh);
          return fresh;
        })
        .whenComplete(() => _enrolling = null));
    return fresh.token;
  }

  Future<_StoredToken?> _readStored(String key) async {
    try {
      return _decode(await _store.read(key));
    } catch (e) {
      debugPrint('[GatewayCredentials] stored token unreadable: $e');
      return null;
    }
  }

  Future<void> _writeStored(String key, _StoredToken token) async {
    try {
      await _store.write(
        key,
        jsonEncode({
          'token': token.token,
          'expires_at': token.expiresAt.millisecondsSinceEpoch,
        }),
      );
    } catch (e) {
      debugPrint('[GatewayCredentials] token not persisted: $e');
    }
  }

  bool _isFresh(DateTime expiresAt) =>
      expiresAt.isAfter(_now().add(_expiryMargin));

  Map<String, dynamic>? _decodeJsonMap(String? raw) {
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  _StoredToken? _decode(String? raw) {
    final json = _decodeJsonMap(raw);
    final token = json?['token'];
    final expiresAt = json?['expires_at'];
    if (token is! String || expiresAt is! int) return null;
    return (
      token: token,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt),
    );
  }

  Future<_StoredToken> _enroll() async {
    try {
      return await retryWithBackoff(
        _enrollOnce,
        label: 'POST /calls/enroll',
        maxAttempts: 3,
        baseDelay: const Duration(milliseconds: 150),
        maxDelay: const Duration(milliseconds: 1500),
        retryIf: (error) =>
            error is SocketException ||
            (error is GatewayEnrollmentException &&
                (error.statusCode ?? 0) >= 500),
      );
    } on SocketException catch (e) {
      throw GatewayEnrollmentException('enroll unreachable: $e');
    }
  }

  Future<_StoredToken> _enrollOnce() async {
    final response = await _httpClient.post(
      gatewayEnrollUri(client),
      headers: {
        'Authorization': await bearerAuthorization(client),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'device_id': client.deviceID}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GatewayEnrollmentException(
        'HTTP ${response.statusCode} from enroll: ${response.body}',
        statusCode: response.statusCode,
      );
    }
    return _decodeEnrollment(response.body, response.statusCode);
  }

  _StoredToken _decodeEnrollment(String body, int statusCode) {
    final json = _decodeJsonMap(body);
    final token = json?['token'];
    if (token is! String || token.isEmpty) {
      throw GatewayEnrollmentException(
        'enroll response missing token (status $statusCode)',
      );
    }
    final expiresAtMs = json?['expires_at'];
    if (expiresAtMs is! int) {
      throw GatewayEnrollmentException(
        'enroll response missing expires_at (status $statusCode)',
      );
    }
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresAtMs);
    if (!_isFresh(expiresAt)) {
      throw GatewayEnrollmentException(
        'enroll returned an already-expired token',
      );
    }
    return (token: token, expiresAt: expiresAt);
  }

  Future<void> revoke() async {
    final key = _storageKey;
    final stored = _cached ?? await _readStored(key);
    _cached = null;
    try {
      await _store.delete(key);
    } catch (_) {}
    if (stored == null) return;
    await _httpClient.delete(
      gatewayEnrollUri(client),
      headers: {'Authorization': 'Bearer ${stored.token}'},
    );
  }

  void close() {
    if (_ownsHttpClient) _httpClient.close();
  }
}
