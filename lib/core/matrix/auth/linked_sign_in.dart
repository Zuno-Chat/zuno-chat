import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:matrix/matrix.dart';

import '../../l10n/l10n.dart';
import '../http/typed_server_answers.dart';
import 'auth_error_message.dart';

const _codeTag = 'ZUNO-SIGN-IN';
const _codeVersion = '1';
final _serverName = RegExp(
  r'^(\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*)(:\d{1,5})?$',
);

class LinkedSignInCode {
  final String server;
  final String token;

  const LinkedSignInCode({required this.server, required this.token});

  String encode() => '$_codeTag $_codeVersion $server $token';

  String get typed => '$server\n${groupedSignInCode(token)}';

  static LinkedSignInCode? decode(String raw) {
    final parts = raw.trim().split(RegExp(r'\s+'));
    if (parts.length != 4 || parts[0] != _codeTag || parts[1] != _codeVersion) {
      return null;
    }
    return LinkedSignInCode(server: parts[2], token: parts[3]);
  }

  static LinkedSignInCode? parseTyped(String raw) {
    if (decode(raw) case final code?) return code;
    final words = raw.trim().split(RegExp(r'\s+'));
    final server = words.first;
    if (words.length < 2 ||
        !server.contains(RegExp('[.:]')) ||
        !_serverName.hasMatch(server)) {
      return null;
    }
    return LinkedSignInCode(server: server, token: words.skip(1).join());
  }
}

class IssuedSignInCode {
  final LinkedSignInCode code;
  final DateTime expiresAt;

  const IssuedSignInCode({required this.code, required this.expiresAt});
}

Future<IssuedSignInCode> issueLinkedSignInCode(Client client) async {
  GenerateLoginTokenResponse? response;
  await client.uiaRequestBackground<void>((auth) async {
    response = await client.generateLoginToken(auth: auth);
  });
  final granted = response!;
  return IssuedSignInCode(
    code: LinkedSignInCode(
      server: client.userID!.domain!,
      token: granted.loginToken,
    ),
    expiresAt: clock.now().add(Duration(milliseconds: granted.expiresInMs)),
  );
}

class SignInCodeForAnotherServer implements Exception {
  final String server;

  const SignInCodeForAnotherServer(this.server);
}

Future<void> signInWithLinkedCode(
  Client client,
  LinkedSignInCode code, {
  required Uri chosenServer,
  required String deviceDisplayName,
}) async {
  if (Uri.tryParse('https://${code.server}')?.host != chosenServer.host) {
    throw SignInCodeForAnotherServer(code.server);
  }
  await client.login(
    LoginType.mLoginToken,
    token: code.token,
    initialDeviceDisplayName: deviceDisplayName,
    refreshToken: true,
  );
}

String groupedSignInCode(String token) {
  final groups = <String>[];
  for (var i = 0; i < token.length; i += 4) {
    groups.add(token.substring(i, math.min(i + 4, token.length)));
  }
  return groups.join(' ');
}

String linkedSignInErrorMessage(AppLocalizations l10n, Object error) {
  if (error is SignInCodeForAnotherServer) {
    return l10n.matrixLinkedSignInOtherServer(error.server);
  }
  if (error is MatrixException && error.error == MatrixError.M_FORBIDDEN) {
    return l10n.matrixLinkedSignInInvalid;
  }
  return loginErrorMessage(l10n, error);
}

bool isLinkedSignInRefusal(Object error) =>
    error is SignInCodeForAnotherServer || isLoginRefusal(error);

bool isSignInCodeIssueRefusal(Object error) =>
    isRateLimit(error) ||
    (error is MatrixException && error.error == MatrixError.M_UNRECOGNIZED);

String signInCodeIssueErrorMessage(AppLocalizations l10n, Object error) {
  if (isRateLimit(error)) return loginErrorMessage(l10n, error);
  if (error case MatrixException(error: MatrixError.M_UNRECOGNIZED)) {
    return l10n.matrixLinkedSignInUnsupported;
  }
  return l10n.matrixLinkedSignInIssueFailed;
}
