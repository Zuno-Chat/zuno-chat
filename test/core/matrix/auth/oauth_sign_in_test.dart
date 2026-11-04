import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/auth/auth_browser.dart';
import 'package:zuno/core/matrix/auth/oauth_sign_in.dart';
import 'package:zuno/core/matrix/http/typed_server_answers.dart';
import 'package:zuno/core/navigation/zuno_links.dart';

import '../../../helpers/caught_reports.dart';
import '../../../helpers/fake_http.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/oauth_server.dart';
import '../../../helpers/sha256_only_vodozemac.dart';

void main() {
  late OAuthServer server;
  late Client client;

  http.Request? requestTo(String method, String path) =>
      server.requestTo(method, path);

  setUp(() {
    installSha256OnlyVodozemac();
    addTearDown(removeSha256OnlyVodozemac);
    server = OAuthServer();
    client = buildTestClient(
      database: OAuthSignInDatabase(),
      httpClient: FakeHttpClient(server.answer),
    )..homeserver = Uri.parse('https://example.org');
  });

  Future<void> signInWithoutEncryptionSetup(OAuthGrant grant) {
    removeSha256OnlyVodozemac();
    return completeOAuthSignIn(
      client,
      grant,
      deviceDisplayName: 'Zuno on Android',
    );
  }

  AuthBrowser browserAnswering(Uri Function(Uri authorization) answer) =>
      (authorization, scheme) async {
        expect(scheme, zunoOAuthCallbackScheme);
        return answer(authorization);
      };

  test("registers as a native client with Zuno's metadata", () async {
    await authorizeInBrowser(
      client,
      browser: browserAnswering((a) => oauthCallbackFor(a)),
    );

    final body = jsonDecode(
      requestTo('POST', '/register')!.body,
    ) as Map<String, Object?>;
    expect(body['redirect_uris'], ['chat.zuno:/oauth']);
    expect(body['application_type'], 'native');
    expect(body['client_name'], 'Zuno');
    expect(body['client_uri'], 'https://zuno.chat');
    expect(body['token_endpoint_auth_method'], 'none');
    expect(body['tos_uri'], termsUri.toString());
    expect(body['policy_uri'], privacyPolicyUri.toString());
    expect(body['logo_uri'], 'https://zuno.chat/assets/apple-touch-icon.png');
  });

  test('asks for the stable scopes', () async {
    late Uri authorization;
    await authorizeInBrowser(
      client,
      browser: browserAnswering((a) {
        authorization = a;
        return oauthCallbackFor(a);
      }),
    );

    final scopes = authorization.queryParameters['scope']!.split(' ');
    expect(scopes, hasLength(2));
    expect(scopes, contains('urn:matrix:client:api:*'));
    final device = scopes.singleWhere(
      (s) => s.startsWith('urn:matrix:client:device:'),
    );
    expect(
      device.substring('urn:matrix:client:device:'.length).length,
      greaterThanOrEqualTo(10),
    );
    expect(authorization.toString(), isNot(contains('msc2967')));
    expect(authorization.queryParameters['code_challenge_method'], 'S256');
    expect(authorization.queryParameters['client_id'], 'client-1');
    expect(authorization.queryParameters['redirect_uri'], 'chat.zuno:/oauth');
  });

  test('create adds prompt=create', () async {
    final prompts = <String?>[];
    for (final createAccount in [true, false]) {
      await authorizeInBrowser(
        client,
        createAccount: createAccount,
        browser: browserAnswering((a) {
          prompts.add(a.queryParameters['prompt']);
          return oauthCallbackFor(a);
        }),
      );
    }

    expect(prompts, ['create', null]);
  });

  test('signs in and names the device', () async {
    final grant = await authorizeInBrowser(
      client,
      browser: browserAnswering((a) => oauthCallbackFor(a)),
    );

    await signInWithoutEncryptionSetup(grant);

    final token = Uri.splitQueryString(requestTo('POST', '/token')!.body);
    expect(token['code'], 'c1');
    expect(token['grant_type'], 'authorization_code');
    expect(token['client_id'], 'client-1');
    expect(client.isLogged(), isTrue);
    final rename = server.requests.singleWhere((r) => r.method == 'PUT');
    expect(rename.url.path, '/_matrix/client/v3/devices/ABCDEFGHIJ');
    expect(jsonDecode(rename.body), {'display_name': 'Zuno on Android'});
  });

  test('a refused code exchange carries the OAuth error code', () async {
    server.tokenAnswer = http.Response(
      jsonEncode({'error': 'invalid_grant'}),
      400,
    );
    final grant = await authorizeInBrowser(
      client,
      browser: browserAnswering((a) => oauthCallbackFor(a)),
    );

    await expectLater(
      signInWithoutEncryptionSetup(grant),
      throwsA(
        isA<OAuthSignInFailed>().having(
          (e) => e.reason,
          'reason',
          'invalid_grant',
        ),
      ),
    );
    expect(client.isLogged(), isFalse);
  });

  test('a refused client registration carries the OAuth error code', () async {
    server.registrationAnswer = http.Response(
      jsonEncode({
        'error': 'invalid_client_metadata',
        'error_description': 'redirect_uris is invalid',
      }),
      400,
    );
    var opened = false;

    await expectLater(
      authorizeInBrowser(
        client,
        browser: (_, _) async {
          opened = true;
          throw StateError('the browser opened');
        },
      ),
      throwsA(
        isA<ServerAnswerFailed>()
            .having((e) => e.statusCode, 'status', 400)
            .having(
              (e) => e.oauthError,
              'oauthError',
              'invalid_client_metadata',
            ),
      ),
    );
    expect(opened, isFalse);
  });

  test('state mismatch is refused before the token request', () async {
    await expectLater(
      authorizeInBrowser(
        client,
        browser: browserAnswering((a) => oauthCallbackFor(a, state: 'other')),
      ),
      throwsA(
        isA<OAuthSignInFailed>().having(
          (e) => e.reason,
          'reason',
          'state_mismatch',
        ),
      ),
    );

    expect(requestTo('POST', '/token'), isNull);
    expect(client.isLogged(), isFalse);
  });

  test('access_denied is a cancel', () async {
    await expectLater(
      authorizeInBrowser(
        client,
        browser: browserAnswering(
          (a) => Uri.parse(
            'chat.zuno:/oauth?error=access_denied'
            '&state=${a.queryParameters['state']}',
          ),
        ),
      ),
      throwsA(isA<OAuthSignInCancelled>()),
    );

    expect(requestTo('POST', '/token'), isNull);
  });

  test("the browser's cancel passes through", () async {
    await expectLater(
      authorizeInBrowser(
        client,
        browser: (_, _) async => throw const OAuthSignInCancelled(),
      ),
      throwsA(isA<OAuthSignInCancelled>()),
    );

    expect(requestTo('POST', '/token'), isNull);
  });

  test('a device rename failure keeps the sign-in', () async {
    server.deviceAnswer = 404;
    final grant = await authorizeInBrowser(
      client,
      browser: browserAnswering((a) => oauthCallbackFor(a)),
    );

    final reports = await reportsDuring(
      () => signInWithoutEncryptionSetup(grant),
    );

    expect(reports, ['name this device']);
    expect(
      requestTo('PUT', '/_matrix/client/v3/devices/ABCDEFGHIJ'),
      isNotNull,
    );
    expect(client.isLogged(), isTrue);
  });

  group('parseOAuthCallback', () {
    test('returns the code', () {
      expect(
        parseOAuthCallback(
          Uri.parse('chat.zuno:/oauth?code=abc&state=s'),
          expectedState: 's',
        ),
        'abc',
      );
    });

    test('another error is refused with its code', () {
      expect(
        () => parseOAuthCallback(
          Uri.parse('chat.zuno:/oauth?error=server_error&state=s'),
          expectedState: 's',
        ),
        throwsA(
          isA<OAuthSignInFailed>().having(
            (e) => e.reason,
            'reason',
            'server_error',
          ),
        ),
      );
    });

    test('a refusal reports its code and nothing else', () {
      expect(
        const OAuthSignInFailed('invalid_scope').toString(),
        'OAuthSignInFailed(invalid_scope)',
      );
    });

    test('a missing code is refused', () {
      expect(
        () => parseOAuthCallback(
          Uri.parse('chat.zuno:/oauth?state=s'),
          expectedState: 's',
        ),
        throwsA(
          isA<OAuthSignInFailed>().having(
            (e) => e.reason,
            'reason',
            'missing_code',
          ),
        ),
      );
    });

    test('a forged state beats an access_denied', () {
      expect(
        () => parseOAuthCallback(
          Uri.parse('chat.zuno:/oauth?error=access_denied&state=x'),
          expectedState: 's',
        ),
        throwsA(isA<OAuthSignInFailed>()),
      );
    });
  });
}
