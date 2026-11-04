import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import '../errors/caught_errors.dart';
import '../errors/connection_error.dart';
import 'registration_support.dart';
import 'typed_server_answers.dart';

sealed class SignIn {
  const SignIn();
}

final class PasswordSignIn extends SignIn {
  const PasswordSignIn();

  @override
  bool operator ==(Object other) => other is PasswordSignIn;

  @override
  int get hashCode => (PasswordSignIn).hashCode;
}

final class OAuthSignIn extends SignIn {
  const OAuthSignIn({required this.canCreateAccount});

  final bool canCreateAccount;

  @override
  bool operator ==(Object other) =>
      other is OAuthSignIn && other.canCreateAccount == canCreateAccount;

  @override
  int get hashCode => Object.hash(OAuthSignIn, canCreateAccount);
}

class ServerChoice {
  const ServerChoice(
    this.homeserver, {
    required this.apiHost,
    this.signIn = const PasswordSignIn(),
  });

  final Uri homeserver;
  final Uri apiHost;
  final SignIn signIn;

  @override
  bool operator ==(Object other) =>
      other is ServerChoice &&
      other.homeserver == homeserver &&
      other.apiHost == apiHost &&
      other.signIn == signIn;

  @override
  int get hashCode => Object.hash(homeserver, apiHost, signIn);
}

class UnsupportedSignInException implements Exception {
  const UnsupportedSignInException();
}

enum SignUpPath { open, code, oauth, closed, unknown }

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
  final api = _ServerCheckApi(apiHost, client.httpClient);
  final versions = api.getVersions();
  final authMetadata = _authMetadata(api)..ignore();
  final loginFlows = _loginFlows(api)..ignore();
  await versions;
  if (await authMetadata case final metadata?) {
    return ServerChoice(
      server,
      apiHost: apiHost,
      signIn: OAuthSignIn(
        canCreateAccount:
            metadata.promptValuesSupported?.contains('create') ?? false,
      ),
    );
  }
  final flows = await loginFlows;
  if (flows.isNotEmpty &&
      !flows.any((flow) => flow.type == AuthenticationTypes.password)) {
    throw const UnsupportedSignInException();
  }
  return ServerChoice(server, apiHost: apiHost);
}

class _ServerCheckApi extends MatrixApi with TypedServerAnswers {
  _ServerCheckApi(Uri homeserver, http.Client httpClient)
    : super(homeserver: homeserver, httpClient: httpClient);
}

Future<Uri?> _discoveredApiHost(Client client, Uri server) async {
  final DiscoveryInformation discovery;
  try {
    discovery = await _ServerCheckApi(
      Uri.https(server.host, ''),
      client.httpClient,
    ).getWellknown();
  } catch (error, stack) {
    if (isConnectionError(error) ||
        error is MatrixException ||
        error is ServerAnswerFailed ||
        isNotMatrixAnswer(error)) {
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

Future<GetAuthMetadataResponse?> _authMetadata(MatrixApi api) async {
  try {
    return await api.getAuthMetadata();
  } catch (error) {
    if (meansNoAuthMetadata(error)) return null;
    rethrow;
  }
}

bool meansNoAuthMetadata(Object error) => switch (error) {
  MatrixException(
    error: MatrixError.M_UNRECOGNIZED || MatrixError.M_NOT_FOUND,
  ) ||
  ServerAnswerFailed(statusCode: 404) => true,
  _ => false,
};

Future<List<LoginFlow>> _loginFlows(MatrixApi api) async {
  try {
    return await api.getLoginFlows() ?? const [];
  } on MatrixException {
    return const [];
  }
}
