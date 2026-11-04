import 'package:matrix/matrix.dart';

import '../errors/caught_errors.dart';
import '../errors/connection_error.dart';
import 'registration_support.dart';

class ServerChoice {
  const ServerChoice(this.homeserver, {required this.apiHost});

  final Uri homeserver;
  final Uri apiHost;

  @override
  bool operator ==(Object other) =>
      other is ServerChoice &&
      other.homeserver == homeserver &&
      other.apiHost == apiHost;

  @override
  int get hashCode => Object.hash(homeserver, apiHost);
}

enum SignUpPath { open, code, closed, unknown }

SignUpPath signUpPathFrom(RegistrationSupport support) =>
    switch (support.availability) {
      RegistrationAvailability.disabled ||
      RegistrationAvailability.unsupportedFlow => SignUpPath.closed,
      RegistrationAvailability.unknown => SignUpPath.unknown,
      RegistrationAvailability.available
          when support.requiresRegistrationToken =>
        SignUpPath.code,
      RegistrationAvailability.available => SignUpPath.open,
    };

Future<ServerChoice> checkServer(Client client, Uri server) async {
  final apiHost =
      await _discoveredApiHost(client, server) ?? server.stripTrailingSlash();
  final api = MatrixApi(homeserver: apiHost, httpClient: client.httpClient);
  final versions = api.getVersions();
  final loginFlows = _loginFlows(api)..ignore();
  await versions;
  final flows = await loginFlows;
  final supported = client.supportedLoginTypes;
  if (flows.isNotEmpty && !flows.any((flow) => supported.contains(flow.type))) {
    throw BadServerLoginTypesException(
      flows.map((flow) => flow.type).toSet(),
      supported,
    );
  }
  return ServerChoice(server, apiHost: apiHost);
}

Future<Uri?> _discoveredApiHost(Client client, Uri server) async {
  final DiscoveryInformation discovery;
  try {
    discovery = await MatrixApi(
      homeserver: Uri.https(server.host, ''),
      httpClient: client.httpClient,
    ).getWellknown();
  } catch (error, stack) {
    if (error is MatrixException ||
        isNotMatrixAnswer(error) ||
        isConnectionError(error)) {
      return null;
    }
    if (error is! Exception) rethrow;
    reportCaught('read discovery file', error, stack);
    return null;
  }
  final apiHost = discovery.mHomeserver.baseUrl.stripTrailingSlash();
  final accepted =
      apiHost.isAbsolute &&
      apiHost.host.isNotEmpty &&
      (apiHost.isScheme('https') || apiHost.isScheme('http'));
  return accepted ? apiHost : null;
}

Future<List<LoginFlow>> _loginFlows(MatrixApi api) async {
  try {
    return await api.getLoginFlows() ?? const [];
  } on MatrixException {
    return const [];
  }
}
