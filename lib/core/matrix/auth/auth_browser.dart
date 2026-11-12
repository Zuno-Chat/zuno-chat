import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

typedef AuthBrowser = Future<Uri> Function(
  Uri authorizationUri,
  String callbackScheme,
);

final authBrowserProvider = Provider<AuthBrowser>((_) => systemAuthBrowser);

class OAuthSignInCancelled implements Exception {
  const OAuthSignInCancelled();
}

class AuthBrowserUnavailable implements Exception {
  const AuthBrowserUnavailable();
}

class OAuthSignInFailed implements Exception {
  const OAuthSignInFailed(this.reason);

  final String reason;

  @override
  String toString() => 'OAuthSignInFailed($reason)';
}

Future<bool> showUntilClosed(
  AuthBrowser browser,
  Uri page, {
  required String callbackScheme,
}) async {
  try {
    await browser(page, callbackScheme);
  } on OAuthSignInCancelled {
    return true;
  } on AuthBrowserUnavailable {
    return false;
  }
  return true;
}

Future<Uri> systemAuthBrowser(
  Uri authorizationUri,
  String callbackScheme,
) async {
  try {
    final callback = await FlutterWebAuth2.authenticate(
      url: authorizationUri.toString(),
      callbackUrlScheme: callbackScheme,
      options: const FlutterWebAuth2Options(preferEphemeral: true),
    );
    try {
      return Uri.parse(callback);
    } on FormatException {
      throw const OAuthSignInFailed('bad_callback');
    }
  } on PlatformException catch (e) {
    if (e.code == 'CANCELED') throw const OAuthSignInCancelled();
    if (e.code == 'NO_BROWSER') throw const AuthBrowserUnavailable();
    throw OAuthSignInFailed(e.code);
  }
}
