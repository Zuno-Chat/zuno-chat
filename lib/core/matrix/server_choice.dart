import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import '../errors/caught_errors.dart';
import '../errors/connection_error.dart';
import 'registration_support.dart';

const zunoRegisterAnnouncementKey = 'chat.zuno.register';

class ServerChoice {
  const ServerChoice(
    this.homeserver, {
    required this.apiHost,
    this.mailsSignUpCodes = false,
  });

  final Uri homeserver;
  final Uri apiHost;
  final bool? mailsSignUpCodes;

  @override
  bool operator ==(Object other) =>
      other is ServerChoice &&
      other.homeserver == homeserver &&
      other.apiHost == apiHost &&
      other.mailsSignUpCodes == mailsSignUpCodes;

  @override
  int get hashCode => Object.hash(homeserver, apiHost, mailsSignUpCodes);
}

enum SignUpPath { open, emailedCode, adminCode, closed, unknown }

SignUpPath signUpPathFrom(
  RegistrationSupport support, {
  required bool? mailsSignUpCodes,
}) => switch (support.availability) {
  RegistrationAvailability.disabled ||
  RegistrationAvailability.unsupportedFlow => SignUpPath.closed,
  RegistrationAvailability.unknown => SignUpPath.unknown,
  RegistrationAvailability.available when !support.requiresRegistrationToken =>
    SignUpPath.open,
  RegistrationAvailability.available => switch (mailsSignUpCodes) {
    true => SignUpPath.emailedCode,
    false => SignUpPath.adminCode,
    null => SignUpPath.unknown,
  },
};

typedef Discovered = ({Uri? homeserver, bool? mailsSignUpCodes});

Future<Discovered> readDiscovery(Client client, Uri server) async {
  const unknown = (homeserver: null, mailsSignUpCodes: null);
  const nothing = (homeserver: null, mailsSignUpCodes: false);
  final http.Response response;
  try {
    response = await client.httpClient.get(
      Uri.https(server.host, '/.well-known/matrix/client'),
    );
  } on Exception catch (error, stack) {
    if (!isConnectionError(error)) {
      reportCaught('read discovery file', error, stack);
    }
    return unknown;
  }
  if (response.statusCode >= 500 || response.statusCode == 429) return unknown;
  if (response.statusCode != 200) return nothing;
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(response.bodyBytes));
  } on FormatException {
    return nothing;
  }
  return decoded is Map<String, Object?> ? _discoveredIn(decoded) : nothing;
}

Discovered _discoveredIn(Map<String, Object?> content) {
  if (content case {'m.homeserver': {'base_url': final String base}}) {
    if (Uri.tryParse(base) case final apiHost?
        when apiHost.isAbsolute &&
            apiHost.host.isNotEmpty &&
            (apiHost.scheme == 'https' || apiHost.scheme == 'http')) {
      return (
        homeserver: apiHost,
        mailsSignUpCodes: content[zunoRegisterAnnouncementKey] is Map,
      );
    }
  }
  return (homeserver: null, mailsSignUpCodes: false);
}
