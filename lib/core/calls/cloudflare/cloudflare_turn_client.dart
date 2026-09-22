import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import '../../errors/retry_backoff.dart';
import 'calls_module.dart';

class CloudflareTurnException implements Exception {
  final String message;
  final int? statusCode;
  final Duration? retryAfter;

  CloudflareTurnException(this.message, {this.statusCode, this.retryAfter});

  @override
  String toString() => 'CloudflareTurnException: $message';
}

Future<List<Map<String, Object?>>> fetchCloudflareIceServers({
  required Uri credentialsUri,
  required Future<String> Function() authorization,
  http.Client? httpClient,
}) async {
  final client = httpClient ?? http.Client();
  try {
    return await retryWithBackoff(
      () => _fetchOnce(client, credentialsUri, authorization),
      label: 'POST ${credentialsUri.path}',
      maxAttempts: 3,
      baseDelay: const Duration(milliseconds: 150),
      maxDelay: const Duration(milliseconds: 1500),
      retryIf: (error) =>
          error is SocketException ||
          error is http.ClientException ||
          (error is CloudflareTurnException && error.statusCode == 429),
      retryAfter: (error) =>
          error is CloudflareTurnException ? error.retryAfter : null,
    );
  } finally {
    if (httpClient == null) client.close();
  }
}

Future<List<Map<String, Object?>>> _fetchOnce(
  http.Client client,
  Uri credentialsUri,
  Future<String> Function() authorization,
) async {
  final response = await client.post(
    credentialsUri,
    headers: {'Authorization': await authorization()},
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw CloudflareTurnException(
      'HTTP ${response.statusCode} from TURN credentials: ${response.body}',
      statusCode: response.statusCode,
      retryAfter: retryAfterOf(response),
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
