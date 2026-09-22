import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException, TlsException;

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'gateway_origin.dart';

enum RegistrationCodeOutcome {
  sent,
  invalidEmail,
  rateLimited,
  unavailable,
  serverError,
  offline,
}

Uri? registrationCodeUri(Client client) =>
    gatewayOrigin(client, const ['register', 'token']);

bool looksLikeEmail(String value) {
  final trimmed = value.trim();
  if (trimmed.contains(RegExp(r'\s'))) return false;
  final parts = trimmed.split('@');
  if (parts.length != 2) return false;
  final local = parts.first;
  final domain = parts.last;
  if (local.isEmpty) return false;
  final dot = domain.lastIndexOf('.');
  return dot > 0 && dot < domain.length - 1;
}

RegistrationCodeOutcome registrationCodeOutcomeFrom(int statusCode) {
  return switch (statusCode) {
    200 || 202 => RegistrationCodeOutcome.sent,
    400 || 413 => RegistrationCodeOutcome.invalidEmail,
    404 || 503 => RegistrationCodeOutcome.unavailable,
    429 => RegistrationCodeOutcome.rateLimited,
    _ => RegistrationCodeOutcome.serverError,
  };
}

const registrationCodeTimeout = Duration(seconds: 35);

Future<RegistrationCodeOutcome> requestRegistrationCode(
  Client client,
  String email,
) async {
  final uri = registrationCodeUri(client);
  if (uri == null) return RegistrationCodeOutcome.unavailable;
  try {
    final response = await client.httpClient
        .post(
          uri,
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({'email': email.trim()}),
        )
        .timeout(registrationCodeTimeout);
    return registrationCodeOutcomeFrom(response.statusCode);
  } on http.ClientException {
    return RegistrationCodeOutcome.offline;
  } on SocketException {
    return RegistrationCodeOutcome.offline;
  } on TlsException {
    return RegistrationCodeOutcome.offline;
  } on TimeoutException {
    return RegistrationCodeOutcome.offline;
  }
}
