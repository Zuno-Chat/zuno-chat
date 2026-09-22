import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/linked_sign_in.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  group('LinkedSignInCode', () {
    test('round-trips through its QR text', () {
      const code = LinkedSignInCode(server: 'zuno.chat', token: 'syl_abc_def');

      final decoded = LinkedSignInCode.decode(code.encode());

      expect(decoded?.server, 'zuno.chat');
      expect(decoded?.token, 'syl_abc_def');
    });

    test('keeps a token with URL-special characters intact', () {
      const code = LinkedSignInCode(server: 'zuno.chat', token: 'a+b/c=&d');

      expect(LinkedSignInCode.decode(code.encode())?.token, 'a+b/c=&d');
    });

    test('tolerates whitespace around a pasted code', () {
      const code = LinkedSignInCode(server: 'zuno.chat', token: 'syl_abc');

      expect(LinkedSignInCode.decode('  ${code.encode()}\n')?.token, 'syl_abc');
    });

    test('matches its server by host, ignoring case', () {
      const code = LinkedSignInCode(server: 'Zuno.Chat', token: 'syl_abc');

      expect(code.isForServer('zuno.chat'), isTrue);
      expect(code.isForServer('api.zuno.chat'), isFalse);
      expect(code.isForServer(null), isFalse);
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

    test('a typed code loses the spaces the grouping added', () {
      expect(typedSignInCode(' syl_ abcd efgh ij\n'), 'syl_abcdefghij');
    });
  });

  group('issueLinkedSignInCode', () {
    Client clientAnswering(
      http.Response Function(Map<String, Object?> body) answer, {
      List<Map<String, Object?>>? bodies,
    }) {
      return buildTestClient(
          userId: '@alice:example.org',
          httpClient: MockClient((request) async {
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

    http.Response passwordChallenge() => http.Response(
      jsonEncode({
        'session': 's1',
        'flows': [
          {
            'stages': ['m.login.password'],
          },
        ],
        'params': <String, Object?>{},
      }),
      401,
    );

    http.Response issued({int expiresInMs = 300000}) => http.Response(
      jsonEncode({'login_token': 'syl_abc', 'expires_in_ms': expiresInMs}),
      200,
    );

    test('answers the password challenge and returns the code', () async {
      final bodies = <Map<String, Object?>>[];
      final client = clientAnswering(
        (body) => body['auth'] == null ? passwordChallenge() : issued(),
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

      final result = await issueLinkedSignInCode(client, now: () => now);

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
        signInCodeIssueErrorMessage(failure!),
        signInCodesUnsupportedMessage,
      );
    });
  });

  group('signInWithLinkedCode', () {
    test(
      'signs in with the token, a refresh token and a device name',
      () async {
        Map<String, Object?>? loginBody;
        final client = buildTestClient(
          httpClient: MockClient((request) async {
            expect(request.url.path, '/_matrix/client/v3/login');
            loginBody = jsonDecode(request.body) as Map<String, Object?>;
            return http.Response(
              jsonEncode({
                'errcode': 'M_FORBIDDEN',
                'error': 'Invalid login token',
              }),
              403,
            );
          }),
        )..homeserver = Uri.parse('https://example.org');

        await expectLater(
          signInWithLinkedCode(
            client,
            token: 'syl_abc',
            deviceDisplayName: 'Zuno on Android',
          ),
          throwsA(isA<MatrixException>()),
        );

        expect(loginBody?['type'], 'm.login.token');
        expect(loginBody?['token'], 'syl_abc');
        expect(loginBody?['refresh_token'], isTrue);
        expect(loginBody?['initial_device_display_name'], 'Zuno on Android');
        expect(loginBody?.containsKey('password'), isFalse);
      },
    );
  });

  group('error messages', () {
    test('a refused token says the code is not valid', () {
      expect(
        linkedSignInErrorMessage(
          MatrixException.fromJson({
            'errcode': 'M_FORBIDDEN',
            'error': 'Invalid login token',
          }),
        ),
        invalidSignInCodeMessage,
      );
    });

    test('other sign-in failures keep their usual wording', () {
      expect(
        linkedSignInErrorMessage(
          MatrixException.fromJson({
            'errcode': 'M_USER_DEACTIVATED',
            'error': 'deactivated',
          }),
        ),
        'This account is deactivated',
      );
    });

    test('issuing a code fails with a generic message otherwise', () {
      expect(
        signInCodeIssueErrorMessage(StateError('boom')),
        signInCodeIssueFailedMessage,
      );
    });
  });
}
