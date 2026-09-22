import 'dart:math' as math;

import 'package:matrix/matrix.dart';

import 'auth_error_message.dart';

const _codeTag = 'ZUNO-SIGN-IN';
const _codeVersion = '1';

class LinkedSignInCode {
  final String server;
  final String token;

  const LinkedSignInCode({required this.server, required this.token});

  String encode() => '$_codeTag $_codeVersion $server $token';

  bool isForServer(String? host) =>
      host != null && server.toLowerCase() == host.toLowerCase();

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

Future<IssuedSignInCode> issueLinkedSignInCode(
  Client client, {
  DateTime Function() now = DateTime.now,
}) async {
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
    expiresAt: now().add(Duration(milliseconds: granted.expiresInMs)),
  );
}

Future<void> signInWithLinkedCode(
  Client client, {
  required String token,
  required String deviceDisplayName,
}) => client.login(
  LoginType.mLoginToken,
  token: token,
  initialDeviceDisplayName: deviceDisplayName,
  refreshToken: true,
);

String typedSignInCode(String raw) => raw.replaceAll(RegExp(r'\s'), '');

String groupedSignInCode(String token) {
  final groups = <String>[];
  for (var i = 0; i < token.length; i += 4) {
    groups.add(token.substring(i, math.min(i + 4, token.length)));
  }
  return groups.join(' ');
}

const invalidSignInCodeMessage =
    'That code is not valid or has expired. Make a new one on your other '
    'device.';
const notASignInCodeMessage = 'That is not a Zuno sign-in code.';
String codeForAnotherServerMessage(String server) =>
    'This code is for $server. Change the server on the sign-in screen '
    'first.';
const signInCodesUnsupportedMessage = 'This server cannot make sign-in codes.';
const signInCodeIssueFailedMessage =
    'Could not make a code. Check your connection and try again.';

String linkedSignInErrorMessage(Object error) {
  if (error is MatrixException && error.error == MatrixError.M_FORBIDDEN) {
    return invalidSignInCodeMessage;
  }
  return loginErrorMessage(error);
}

String signInCodeIssueErrorMessage(Object error) {
  if (error is MatrixException) {
    return switch (error.error) {
      MatrixError.M_UNRECOGNIZED => signInCodesUnsupportedMessage,
      MatrixError.M_LIMIT_EXCEEDED => loginErrorMessage(error),
      _ => signInCodeIssueFailedMessage,
    };
  }
  return signInCodeIssueFailedMessage;
}
