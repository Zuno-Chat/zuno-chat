import 'package:matrix/matrix.dart';

import '../errors/best_effort.dart';
import '../navigation/zuno_links.dart';
import 'auth_browser.dart';

final zunoOAuthRedirect = Uri.parse('chat.zuno:/oauth');
final zunoOAuthCallbackScheme = zunoOAuthRedirect.scheme;

final zunoOidcClientInformation = OidcClientInformation(
  clientName: 'Zuno',
  clientUri: zunoWebsite,
  logoUri: zunoLogoUri,
  tosUri: termsUri,
  policyUri: privacyPolicyUri,
);

Set<String> zunoOAuthScopes(String deviceId) => {
  'urn:matrix:client:api:*',
  'urn:matrix:client:device:$deviceId',
};

class OAuthGrant {
  const OAuthGrant(this.session, this.code);

  final OidcLoginSession session;
  final String code;
}

String parseOAuthCallback(Uri callback, {required String expectedState}) {
  final query = callback.queryParameters;
  if (query['state'] != expectedState) {
    throw const OAuthSignInFailed('state_mismatch');
  }
  final error = query['error'];
  if (error == 'access_denied') throw const OAuthSignInCancelled();
  if (error != null) throw OAuthSignInFailed(error);
  final code = query['code'];
  if (code == null || code.isEmpty) {
    throw const OAuthSignInFailed('missing_code');
  }
  return code;
}

Future<OAuthGrant> authorizeInBrowser(
  Client client, {
  required AuthBrowser browser,
  bool createAccount = false,
}) async {
  final clientData = await client.registerOidcClient(
    redirectUris: [zunoOAuthRedirect],
    applicationType: OidcApplicationType.native,
    clientInformation: zunoOidcClientInformation,
  );
  final session = await client.initOidcLoginSession(
    oidcClientData: clientData,
    redirectUri: zunoOAuthRedirect,
    scopes: zunoOAuthScopes(generateRandomDeviceId()),
    prompt: createAccount ? 'create' : null,
  );
  final callback = await browser(
    session.authenticationUri,
    zunoOAuthCallbackScheme,
  );
  final code = parseOAuthCallback(callback, expectedState: session.state);
  return OAuthGrant(session, code);
}

Future<void> completeOAuthSignIn(
  Client client,
  OAuthGrant grant, {
  required String deviceDisplayName,
}) async {
  try {
    await client.oidcLogin(
      session: grant.session,
      code: grant.code,
      state: grant.session.state,
    );
  } on OidcException catch (e) {
    throw OAuthSignInFailed(e.error);
  }
  await runBestEffort(
    () => client.updateDevice(client.deviceID!, displayName: deviceDisplayName),
    label: 'name this device',
  );
}
