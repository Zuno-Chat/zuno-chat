import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:matrix/matrix.dart';

import '../l10n/l10n.dart';
import 'auth_error_message.dart';

const _codeTag = 'ZUNO-SIGN-IN';
const _codeVersion = '1';

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
  Client client, {
  required String? server,
  required String token,
  required Uri chosenServer,
  required String deviceDisplayName,
}) async {
  if (server != null &&
      Uri.tryParse('https://$server')?.host != chosenServer.host) {
    throw SignInCodeForAnotherServer(server);
  }
  await client.login(
    LoginType.mLoginToken,
    token: token,
    initialDeviceDisplayName: deviceDisplayName,
    refreshToken: true,
  );
}

final _serverName = RegExp(
  r'^(\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*)(:\d{1,5})?$',
);

({String? server, String token})? parseTypedSignInCode(String raw) {
  if (LinkedSignInCode.decode(raw) case final code?) {
    return (server: code.server, token: code.token);
  }
  final words = raw.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return null;
  final first = words.first;
  final namesServer =
      first.contains(RegExp('[.:]')) && _serverName.hasMatch(first);
  if (!namesServer) return (server: null, token: words.join());
  if (words.length == 1) return null;
  return (server: first, token: words.skip(1).join());
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

String signInCodeIssueErrorMessage(AppLocalizations l10n, Object error) {
  if (error is MatrixException) {
    return switch (error.error) {
      MatrixError.M_UNRECOGNIZED => l10n.matrixLinkedSignInUnsupported,
      MatrixError.M_LIMIT_EXCEEDED => loginErrorMessage(l10n, error),
      _ => l10n.matrixLinkedSignInIssueFailed,
    };
  }
  return l10n.matrixLinkedSignInIssueFailed;
}
