import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/auth/linked_sign_in.dart';
import 'package:zuno/core/matrix/http/typed_server_answers.dart';

import '../../../helpers/fake_http.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/uia_challenge.dart';

Matcher isCode(String server, String token) => isA<LinkedSignInCode>()
    .having((c) => c.server, 'server', server)
    .having((c) => c.token, 'token', token);

void main() {
  group('LinkedSignInCode', () {
    test('round-trips through its QR text, URL-special characters and '
        'all', () {
      const code = LinkedSignInCode(server: 'zuno.chat', token: 'syl_a+b/c=&d');

      final decoded = LinkedSignInCode.decode(code.encode());

      expect(decoded?.server, 'zuno.chat');
      expect(decoded?.token, 'syl_a+b/c=&d');
    });

    test('tolerates whitespace around a pasted code', () {
      const code = LinkedSignInCode(server: 'zuno.chat', token: 'syl_abc');

      expect(LinkedSignInCode.decode('  ${code.encode()}\n')?.token, 'syl_abc');
    });

    test('is plain text that no camera app opens as a link', () {
      const code = LinkedSignInCode(server: 'zuno.chat', token: 'syl_abc');

      expect(code.encode(), 'ZUNO-SIGN-IN 1 zuno.chat syl_abc');
      expect(Uri.tryParse(code.encode())?.hasScheme, isFalse);
    });

    test('rejects anything that is not a Zuno sign-in code', () {
      for (final raw in [
        '',
        'hello',
        'https://zuno.chat/sign-in#server=zuno.chat&token=syl_abc',
        'zuno://sign-in?server=zuno.chat&token=syl_abc',
        'ZUNO-SIGN-IN 1 zuno.chat',
        'ZUNO-SIGN-IN 1 zuno.chat syl_abc extra',
        'ZUNO-SIGN-IN 2 zuno.chat syl_abc',
        'ZUNO-VERIFY 1 zuno.chat syl_abc',
      ]) {
        expect(LinkedSignInCode.decode(raw), isNull, reason: raw);
      }
    });
  });

  group('typed and grouped codes', () {
    test('groups a token in fours for reading aloud', () {
      expect(groupedSignInCode('syl_abcdefghij'), 'syl_ abcd efgh ij');
    });

    test('shows its server above the grouped token, so a typed code names '
        'its server', () {
      const code = LinkedSignInCode(server: 'example.org', token: 'syl_abc');

      expect(code.typed, 'example.org\nsyl_ abc');
      expect(
        LinkedSignInCode.parseTyped(code.typed),
        isCode('example.org', 'syl_abc'),
      );
    });

    test('a code typed with its server on one line keeps the server', () {
      expect(
        LinkedSignInCode.parseTyped('example.org syl_ abcd efgh'),
        isCode('example.org', 'syl_abcdefgh'),
      );
      expect(
        LinkedSignInCode.parseTyped('localhost:8008 syl_abcd'),
        isCode('localhost:8008', 'syl_abcd'),
      );
    });

    test('a pasted two-line code keeps its server', () {
      expect(
        LinkedSignInCode.parseTyped('zuno.chat\nsyl_ abcd efgh\n'),
        isCode('zuno.chat', 'syl_abcdefgh'),
      );
    });

    test('the text a camera reads from the QR code is a code', () {
      const code = LinkedSignInCode(server: 'zuno.chat', token: 'syl_abcdefgh');

      expect(
        LinkedSignInCode.parseTyped(' ${code.encode()}\n'),
        isCode('zuno.chat', 'syl_abcdefgh'),
      );
    });

    test('a token without its server line is no code', () {
      for (final raw in [
        'syl_abcdefgh',
        ' syl_ abcd efgh ij\n',
        'hello there',
      ]) {
        expect(LinkedSignInCode.parseTyped(raw), isNull, reason: raw);
      }
    });

    test('nothing typed is no code', () {
      expect(LinkedSignInCode.parseTyped(''), isNull);
      expect(LinkedSignInCode.parseTyped(' \n '), isNull);
    });

    test('the server line alone is no code', () {
      for (final raw in ['zuno.chat', 'localhost:8008', '[::1]:8448 \n']) {
        expect(LinkedSignInCode.parseTyped(raw), isNull, reason: raw);
      }
    });
  });

  group('issueLinkedSignInCode', () {
    Client clientAnswering(
      http.Response Function(Map<String, Object?> body) answer, {
      List<Map<String, Object?>>? bodies,
    }) {
      return buildTestClient(
          userId: '@alice:example.org',
          httpClient: FakeHttpClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/_matrix/client/v1/login/get_token');
            final body = jsonDecode(request.body) as Map<String, Object?>;
            bodies?.add(body);
            return answer(body);
          }),
        )
        ..homeserver = Uri.parse('https://example.org')
        ..accessToken = 'syt_token';
    }

    http.Response issued({int expiresInMs = 300000}) => http.Response(
      jsonEncode({'login_token': 'syl_abc', 'expires_in_ms': expiresInMs}),
      200,
    );

    test('answers the password challenge and returns the code', () async {
      final bodies = <Map<String, Object?>>[];
      final client = clientAnswering(
        (body) =>
            body['auth'] == null ? uiaPasswordChallengeResponse() : issued(),
        bodies: bodies,
      );
      client.onUiaRequest.stream.listen((uia) {
        if (uia.state != UiaRequestState.waitForUser) return;
        uia.completeStage(
          AuthenticationPassword(
            session: uia.session,
            password: 'correct horse battery staple',
            identifier: AuthenticationUserIdentifier(
              user: '@alice:example.org',
            ),
          ),
        );
      });
      final now = DateTime(2026, 9, 22, 12);

      final result = await withClock(
        Clock.fixed(now),
        () => issueLinkedSignInCode(client),
      );

      expect(result.code.server, 'example.org');
      expect(result.code.token, 'syl_abc');
      expect(result.expiresAt, now.add(const Duration(minutes: 5)));
      expect(bodies, hasLength(2));
      expect(bodies.first['auth'], isNull);
      expect((bodies.last['auth'] as Map)['type'], 'm.login.password');
    });

    test('a server without the endpoint fails with its own message', () async {
      final client = clientAnswering(
        (_) => http.Response(
          jsonEncode({
            'errcode': 'M_UNRECOGNIZED',
            'error': 'Unrecognized request',
          }),
          404,
        ),
      );

      Object? failure;
      try {
        await issueLinkedSignInCode(client);
      } catch (e) {
        failure = e;
      }

      expect(failure, isA<MatrixException>());
      expect(
        signInCodeIssueErrorMessage(englishLocalizations, failure!),
        'This server cannot make sign-in codes.',
      );
    });
  });

  group('signInWithLinkedCode', () {
    late List<Map<String, Object?>> loginBodies;

    Client loginServer() {
      loginBodies = [];
      return buildTestClient(
        httpClient: FakeHttpClient((request) async {
          expect(request.url.path, '/_matrix/client/v3/login');
          loginBodies.add(jsonDecode(request.body) as Map<String, Object?>);
          return http.Response(
            jsonEncode({
              'errcode': 'M_FORBIDDEN',
              'error': 'Invalid login token',
            }),
            403,
          );
        }),
      )..homeserver = Uri.parse('https://example.org');
    }

    Future<void> signIn({required String server, required Uri chosen}) =>
        signInWithLinkedCode(
          loginServer(),
          LinkedSignInCode(server: server, token: 'syl_abc'),
          chosenServer: chosen,
          deviceDisplayName: 'Zuno on Android',
        );

    test(
      'signs in with the token, a refresh token and a device name',
      () async {
        await expectLater(
          signIn(server: 'example.org', chosen: Uri.https('example.org')),
          throwsA(isA<MatrixException>()),
        );

        final loginBody = loginBodies.single;
        expect(loginBody['type'], 'm.login.token');
        expect(loginBody['token'], 'syl_abc');
        expect(loginBody['refresh_token'], isTrue);
        expect(loginBody['initial_device_display_name'], 'Zuno on Android');
        expect(loginBody.containsKey('password'), isFalse);
      },
    );

    test('matches the server ignoring case', () async {
      await expectLater(
        signIn(server: 'Example.Org', chosen: Uri.https('example.org')),
        throwsA(isA<MatrixException>()),
      );

      expect(loginBodies, hasLength(1));
    });

    for (final (name, server, chosen) in [
      ('with a port', 'localhost:8008', 'http://localhost:8008'),
      ('ignoring the port', 'example.org:8448', 'https://example.org'),
      ('on IPv6', '[::1]', 'https://[::1]'),
      ('on IPv6 with a port', '[::1]:8448', 'https://[::1]:8448'),
    ]) {
      test('matches the chosen server $name', () async {
        await expectLater(
          signIn(server: server, chosen: Uri.parse(chosen)),
          throwsA(isA<MatrixException>()),
        );

        expect(loginBodies.single['token'], 'syl_abc');
      });
    }

    for (final (name, server, chosen) in [
      ('on the same port', 'other.example:8008', 'http://localhost:8008'),
      ('on IPv6', '[::2]', 'https://[::1]'),
      ('that is no server name', '[::1', 'https://[::1]'),
    ]) {
      test('refuses another server $name', () async {
        await expectLater(
          signIn(server: server, chosen: Uri.parse(chosen)),
          throwsA(
            isA<SignInCodeForAnotherServer>().having(
              (e) => e.server,
              'server',
              server,
            ),
          ),
        );

        expect(loginBodies, isEmpty);
      });
    }

    test('a code for another server never reaches the chosen one', () async {
      await expectLater(
        signIn(server: 'other.example', chosen: Uri.https('example.org')),
        throwsA(
          isA<SignInCodeForAnotherServer>().having(
            (e) => e.server,
            'server',
            'other.example',
          ),
        ),
      );

      expect(loginBodies, isEmpty);
    });

    test(
      'a code for a subdomain of the chosen server is another server',
      () async {
        await expectLater(
          signIn(server: 'api.example.org', chosen: Uri.https('example.org')),
          throwsA(isA<SignInCodeForAnotherServer>()),
        );

        expect(loginBodies, isEmpty);
      },
    );
  });

  group('error messages', () {
    test('a refused token says the code is not valid', () {
      expect(
        linkedSignInErrorMessage(
          englishLocalizations,
          MatrixException.fromJson({
            'errcode': 'M_FORBIDDEN',
            'error': 'Invalid login token',
          }),
        ),
        'That code is not valid or has expired. Make a new one on your other device.',
      );
    });

    test('a code for another server names it, and is not reported', () {
      const error = SignInCodeForAnotherServer('other.example');

      expect(
        linkedSignInErrorMessage(englishLocalizations, error),
        'This code is for other.example. Change the server on the sign-in screen first.',
      );
      expect(isLinkedSignInRefusal(error), isTrue);
    });

    test('other sign-in failures keep their usual wording', () {
      expect(
        linkedSignInErrorMessage(
          englishLocalizations,
          MatrixException.fromJson({
            'errcode': 'M_USER_DEACTIVATED',
            'error': 'deactivated',
          }),
        ),
        'This account is deactivated',
      );
    });

    test('a rate limit while issuing a code says how long to wait, with or '
        'without Matrix JSON', () {
      for (final error in <Object>[
        MatrixException.fromJson({
          'errcode': 'M_LIMIT_EXCEEDED',
          'error': 'Too many requests',
          'retry_after_ms': 30000,
        }),
        const ServerAnswerFailed(429, retryAfter: Duration(seconds: 30)),
      ]) {
        expect(
          signInCodeIssueErrorMessage(englishLocalizations, error),
          'Too many attempts. Try again in 30 seconds.',
          reason: '$error',
        );
      }
    });

    test('a rate limit or a server without codes is a refusal, not a '
        'fault', () {
      for (final error in <Object>[
        MatrixException.fromJson({'errcode': 'M_LIMIT_EXCEEDED'}),
        const ServerAnswerFailed(429),
        MatrixException.fromJson({'errcode': 'M_UNRECOGNIZED'}),
      ]) {
        expect(isSignInCodeIssueRefusal(error), isTrue, reason: '$error');
      }
      expect(isSignInCodeIssueRefusal(StateError('boom')), isFalse);
      expect(
        isSignInCodeIssueRefusal(
          MatrixException.fromJson({'errcode': 'M_UNKNOWN'}),
        ),
        isFalse,
      );
    });

    test('issuing a code fails with a generic message otherwise', () {
      expect(
        signInCodeIssueErrorMessage(englishLocalizations, StateError('boom')),
        'Could not make a code. Check your connection and try again.',
      );
    });
  });
}
