import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import '../../errors/retry_backoff.dart';
import 'calls_gateway_credentials.dart';

class CloudflareTurnException implements Exception {
  final String message;
  final int? statusCode;

  CloudflareTurnException(this.message, {this.statusCode});

  @override
  String toString() => 'CloudflareTurnException: $message';
}

Future<List<Map<String, Object?>>> fetchCloudflareIceServers({
  required Uri credentialsUri,
  required GatewayAuthorizationProvider authorizationProvider,
  http.Client? httpClient,
  Duration ttl = const Duration(hours: 24),
}) async {
  final client = httpClient ?? http.Client();
  Future<http.Response> post({required bool refresh}) async => client.post(
    credentialsUri,
    headers: {
      'Authorization': await authorizationProvider(refresh: refresh),
      'Content-Type': 'application/json',
    },
    body: jsonEncode({'ttl': ttl.inSeconds}),
  );
  try {
    return await retryWithBackoff(
      () => _fetchOnce(post),
      label: 'POST ${credentialsUri.path}',
      maxAttempts: 3,
      baseDelay: const Duration(milliseconds: 150),
      maxDelay: const Duration(milliseconds: 1500),
      retryIf: (error) =>
          error is SocketException ||
          error is http.ClientException ||
          (error is CloudflareTurnException && (error.statusCode ?? 0) >= 500),
    );
  } finally {
    if (httpClient == null) client.close();
  }
}

Future<List<Map<String, Object?>>> _fetchOnce(GatewayRequest post) async {
  final response = await sendWithTokenRefresh(post);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw CloudflareTurnException(
      'HTTP ${response.statusCode} from TURN credentials: ${response.body}',
      statusCode: response.statusCode,
    );
  }
  final json = jsonDecode(response.body) as Map<String, dynamic>;
  final iceServers = json['iceServers'];
  if (iceServers is! List) {
    throw CloudflareTurnException(
      'Missing/invalid iceServers in response: ${response.body}',
    );
  }
  return iceServers
      .cast<Map<String, dynamic>>()
      .map((entry) => entry.cast<String, Object?>())
      .toList();
}
