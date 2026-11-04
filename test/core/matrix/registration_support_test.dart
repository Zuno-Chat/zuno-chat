import 'dart:async';
import 'dart:convert';
import 'dart:io' show HandshakeException;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/registration_support.dart';

import '../../helpers/caught_reports.dart';
import '../../helpers/fake_http.dart';
import '../../helpers/fake_matrix.dart';

void main() {
  group('registrationSupportFrom', () {
    test('a 401 offering a dummy-only flow means registration is open, with '
        'no code needed', () {
      final support = registrationSupportFrom(401, {
        'session': 'uia1',
        'flows': [
          {
            'stages': ['m.login.dummy'],
          },
        ],
      });

      expect(support.availability, RegistrationAvailability.available);
      expect(support.requiresRegistrationToken, isFalse);
    });

    test('a 403 means registration is disabled', () {
      final support = registrationSupportFrom(403, {
        'errcode': 'M_FORBIDDEN',
        'error': 'Registration has been disabled',
      });

      expect(support.availability, RegistrationAvailability.disabled);
    });

    test('a captcha-only flow is open but not completable here', () {
      final support = registrationSupportFrom(401, {
        'session': 'uia1',
        'flows': [
          {
            'stages': ['m.login.recaptcha', 'm.login.dummy'],
          },
        ],
      });

      expect(support.availability, RegistrationAvailability.unsupportedFlow);
    });

    test('one completable flow among several is enough', () {
      final support = registrationSupportFrom(401, {
        'flows': [
          {
            'stages': ['m.login.recaptcha'],
          },
          {
            'stages': ['m.login.dummy'],
          },
        ],
      });

      expect(support.availability, RegistrationAvailability.available);
    });

    test('an unexpected status is inconclusive, not open', () {
      expect(
        registrationSupportFrom(500, {}).availability,
        RegistrationAvailability.unknown,
      );
    });

    test('a token-and-dummy flow is completable and needs a code', () {
      final support = registrationSupportFrom(401, {
        'session': 'uia1',
        'flows': [
          {
            'stages': ['m.login.registration_token', 'm.login.dummy'],
          },
        ],
      });

      expect(support.availability, RegistrationAvailability.available);
      expect(support.requiresRegistrationToken, isTrue);
    });

    test('a code-free flow offered alongside a token flow wins', () {
      final support = registrationSupportFrom(401, {
        'flows': [
          {
            'stages': ['m.login.registration_token', 'm.login.dummy'],
          },
          {
            'stages': ['m.login.dummy'],
          },
        ],
      });

      expect(support.availability, RegistrationAvailability.available);
      expect(support.requiresRegistrationToken, isFalse);
    });

    test('a captcha flow beside a token flow still needs a code', () {
      final support = registrationSupportFrom(401, {
        'flows': [
          {
            'stages': ['m.login.recaptcha', 'm.login.dummy'],
          },
          {
            'stages': ['m.login.registration_token', 'm.login.dummy'],
          },
        ],
      });

      expect(support.availability, RegistrationAvailability.available);
      expect(support.requiresRegistrationToken, isTrue);
    });
  });

  group('fetchRegistrationSupport', () {
    final server = Uri.parse('https://example.org');

    test('POSTs an empty body to the register endpoint of the server it is '
        'given, not the one the client last checked', () async {
      late Uri requested;
      final client = buildTestClient(
        httpClient: FakeHttpClient((request) async {
          requested = request.url;
          expect(request.method, 'POST');
          expect(request.body, '{}');
          return http.Response(
            jsonEncode({
              'session': 'uia1',
              'flows': [
                {
                  'stages': ['m.login.dummy'],
                },
              ],
            }),
            401,
          );
        }),
      )..homeserver = Uri.parse('https://candidate.example');

      final support = await fetchRegistrationSupport(client, server);

      expect(
        requested.toString(),
        'https://example.org/_matrix/client/v3/register',
      );
      expect(support.availability, RegistrationAvailability.available);
    });

    for (final (label, failure) in <(String, Exception)>[
      ('a network failure', http.ClientException('offline')),
      ('a TLS failure', const HandshakeException('captive portal')),
    ]) {
      test('$label is inconclusive rather than thrown', () async {
        final client = buildTestClient(
          httpClient: FakeHttpClient((_) async => throw failure),
        );

        expect(
          (await fetchRegistrationSupport(client, server)).availability,
          RegistrationAvailability.unknown,
        );
      });
    }

    test('a homeserver that never answers is inconclusive', () {
      fakeAsync((async) {
        final client = buildTestClient(
          httpClient: FakeHttpClient((_) => Completer<http.Response>().future),
        );

        RegistrationSupport? support;
        fetchRegistrationSupport(
          client,
          server,
        ).then((value) => support = value);
        async.elapse(registrationProbeTimeout);

        expect(support?.availability, RegistrationAvailability.unknown);
      });
    });

    test('a non-JSON body is inconclusive rather than thrown, and no '
        'failure to report', () async {
      final client = buildTestClient(
        httpClient: FakeHttpClient(
          (_) async => http.Response('<html>nope</html>', 401),
        ),
      );

      late RegistrationSupport support;
      final reports = await reportsDuring(
        () async => support = await fetchRegistrationSupport(client, server),
      );

      expect(support.availability, RegistrationAvailability.unknown);
      expect(reports, isEmpty);
    });

    test('a probe that fails some other way is reported', () async {
      final client = buildTestClient(
        httpClient: FakeHttpClient((_) async => throw Exception('closed')),
      );

      final reports = await reportsDuring(
        () => fetchRegistrationSupport(client, server),
      );

      expect(reports, ['probe registration support']);
    });
  });

  group('registrationInputError', () {
    String? errorFor({
      String username = 'alex',
      String password = 'Kestrel-river7',
      String? confirmPassword,
    }) => registrationInputError(
      englishLocalizations,
      username: username,
      password: password,
      confirmPassword: confirmPassword ?? password,
    );

    test('accepts a plain username and a matching password', () {
      expect(errorFor(), isNull);
    });

    test('rejects a full user ID pasted into the username field', () {
      expect(
        errorFor(username: '@alex:example.org'),
        'Enter just a username, without @ or a server name',
      );
    });

    test('rejects a mismatched confirmation', () {
      expect(
        errorFor(confirmPassword: 'somethingelse'),
        'Passwords do not match',
      );
    });

    test('accepts every character the Matrix spec allows, leaving stricter '
        'rules to the server', () {
      for (final username in [
        'alex.smith',
        'alex_smith',
        'alex-smith',
        'a=b',
        'a/b',
        'a+b',
        '_alex',
        '2026',
      ]) {
        expect(errorFor(username: username), isNull, reason: username);
      }
    });

    test('rejects uppercase and anything else outside the spec', () {
      for (final username in ['Alex', 'alex!', 'al ex', 'ålex']) {
        expect(
          errorFor(username: username),
          'Usernames can use a–z, 0–9 and . _ = - / +',
          reason: username,
        );
      }
    });

    test('rejects a password that breaks the Matrix password rule', () {
      expect(errorFor(password: 'kestrel-river7'), 'Add an uppercase letter');
    });

    test('rejects a password the guess checks block, judged against the '
        'username', () {
      expect(
        errorFor(username: 'alexander', password: 'Alexander1!'),
        'Your password contains your username',
      );
    });

    test('rejects a username too long to fit in a user ID', () {
      String? errorWithServer(int length) => registrationInputError(
        englishLocalizations,
        username: 'a' * length,
        password: 'Kestrel-river7',
        confirmPassword: 'Kestrel-river7',
        serverName: 'zuno.chat',
      );

      expect(errorWithServer(244), isNull);
      expect(errorWithServer(245), contains('too long'));
    });
  });

  group('isUiaSessionMismatch', () {
    MatrixException forbidden(String message) =>
        MatrixException.fromJson({'errcode': 'M_FORBIDDEN', 'error': message});

    test("recognises Synapse's replayed-session refusal", () {
      expect(
        isUiaSessionMismatch(
          forbidden(
            'Requested operation has changed during the UI authentication '
            'session.',
          ),
        ),
        isTrue,
      );
    });

    test('is not fooled by the other things M_FORBIDDEN means', () {
      expect(
        isUiaSessionMismatch(forbidden('Registration has been disabled')),
        isFalse,
      );
    });

    test('ignores refusals that are not M_FORBIDDEN at all', () {
      expect(
        isUiaSessionMismatch(
          MatrixException.fromJson({
            'errcode': 'M_USER_IN_USE',
            'error':
                'Requested operation has changed during the UI '
                'authentication session.',
          }),
        ),
        isFalse,
      );
    });
  });

  group('nextRegistrationStep', () {
    MatrixException refusal({
      List<List<String>> flows = const [
        ['m.login.registration_token', 'm.login.dummy'],
      ],
      List<String> completed = const [],
      String? errcode,
      String? error,
    }) {
      return MatrixException.fromJson({
        'session': 'uia1',
        'completed': completed,
        'errcode': ?errcode,
        'error': ?error,
        'flows': [
          for (final stages in flows) {'stages': stages},
        ],
      });
    }

    test('the code stage goes first when a code is required', () {
      final step = nextRegistrationStep(
        refusal: refusal(),
        code: 'ABCDEFGH23',
        lastStageSent: null,
        lastSessionSent: null,
      );

      final auth = (step as SendRegistrationAuth).auth;
      expect(auth.type, 'm.login.registration_token');
      expect(auth.session, 'uia1');
      expect(auth.toJson()['token'], 'ABCDEFGH23');
    });

    test('an accepted code moves on to the dummy stage', () {
      final step = nextRegistrationStep(
        refusal: refusal(completed: const ['m.login.registration_token']),
        code: 'ABCDEFGH23',
        lastStageSent: 'm.login.registration_token',
        lastSessionSent: null,
      );

      final auth = (step as SendRegistrationAuth).auth;
      expect(auth.type, 'm.login.dummy');
      expect(auth.session, 'uia1');
    });

    test('a code the server checked and rejected means it was refused', () {
      final step = nextRegistrationStep(
        refusal: refusal(),
        code: 'ABCDEFGH23',
        lastStageSent: 'm.login.registration_token',
        lastSessionSent: 'uia1',
      );

      expect(step, isA<RegistrationCodeRefused>());
    });

    test('a code stage refused for want of a session is retried with it', () {
      final step = nextRegistrationStep(
        refusal: refusal(
          errcode: 'M_MISSING_PARAM',
          error: 'Missing UIA session',
        ),
        code: 'ABCDEFGH23',
        lastStageSent: 'm.login.registration_token',
        lastSessionSent: null,
      );

      final auth = (step as SendRegistrationAuth).auth;
      expect(auth.type, 'm.login.registration_token');
      expect(auth.session, 'uia1');
      expect(auth.toJson()['token'], 'ABCDEFGH23');
    });

    test(
      'a stage refused before the session was echoed is retried with it',
      () {
        final step = nextRegistrationStep(
          refusal: refusal(
            flows: const [
              ['m.login.dummy'],
            ],
          ),
          code: null,
          lastStageSent: 'm.login.dummy',
          lastSessionSent: null,
        );

        final auth = (step as SendRegistrationAuth).auth;
        expect(auth.type, 'm.login.dummy');
        expect(auth.session, 'uia1');
      },
    );

    test('a stage refused after the session was echoed stops the loop', () {
      final step = nextRegistrationStep(
        refusal: refusal(
          flows: const [
            ['m.login.dummy'],
          ],
        ),
        code: null,
        lastStageSent: 'm.login.dummy',
        lastSessionSent: 'uia1',
      );

      expect(step, isA<RegistrationStalled>());
    });

    test('a refusal offering no flows stops the loop', () {
      final step = nextRegistrationStep(
        refusal: MatrixException.fromJson({
          'session': 'uia1',
          'completed': <String>[],
        }),
        code: null,
        lastStageSent: null,
        lastSessionSent: null,
      );

      expect(step, isA<RegistrationStalled>());
    });

    test('a flow needing a code the user does not have stops the loop', () {
      final step = nextRegistrationStep(
        refusal: refusal(),
        code: null,
        lastStageSent: null,
        lastSessionSent: null,
      );

      expect(step, isA<RegistrationStalled>());
    });

    test('an unsupported flow stops the loop', () {
      final step = nextRegistrationStep(
        refusal: refusal(
          flows: const [
            ['m.login.recaptcha'],
          ],
        ),
        code: null,
        lastStageSent: null,
        lastSessionSent: null,
      );

      expect(step, isA<RegistrationStalled>());
    });

    test('a completed flow with nothing left stops the loop', () {
      final step = nextRegistrationStep(
        refusal: refusal(
          flows: const [
            ['m.login.dummy'],
          ],
          completed: const ['m.login.dummy'],
        ),
        code: null,
        lastStageSent: null,
        lastSessionSent: null,
      );

      expect(step, isA<RegistrationStalled>());
    });

    test('a code-free flow is preferred when both are offered', () {
      final step = nextRegistrationStep(
        refusal: refusal(
          flows: const [
            ['m.login.registration_token', 'm.login.dummy'],
            ['m.login.dummy'],
          ],
        ),
        code: 'ABCDEFGH23',
        lastStageSent: null,
        lastSessionSent: null,
      );

      expect((step as SendRegistrationAuth).auth.type, 'm.login.dummy');
    });
  });

  group('runRegistration', () {
    http.Response uia(Map<String, Object?> body) =>
        http.Response(jsonEncode(body), 401);

    const tokenThenDummyFlows = [
      {
        'stages': ['m.login.registration_token', 'm.login.dummy'],
      },
    ];

    Future<void> register(
      Client client, {
      String? code,
      RegistrationProgress? progress,
    }) => runRegistration(
      client,
      username: 'alice',
      password: 'correct horse battery staple',
      code: code,
      deviceDisplayName: 'Zuno on Android',
      progress: progress,
    );

    ({Client client, List<http.Request> requests}) serverRunning(
      List<http.Response Function()> answers,
    ) {
      final requests = <http.Request>[];
      final client = buildTestClient(
        httpClient: FakeHttpClient((request) async {
          requests.add(request);
          return answers[requests.length - 1]();
        }),
      )..homeserver = Uri.parse('https://example.org');
      return (client: client, requests: requests);
    }

    ({Client client, List<http.Request> requests}) serverAnswering(
      List<http.Response> responses,
    ) => serverRunning([for (final response in responses) () => response]);

    Object? authOf(http.Request request) =>
        (jsonDecode(request.body) as Map<String, Object?>)['auth'];

    http.Response codeAccepted() => uia({
      'session': 'uia1',
      'completed': ['m.login.registration_token'],
      'flows': tokenThenDummyFlows,
    });

    http.Response refused(String errcode, [String error = '']) =>
        http.Response(jsonEncode({'errcode': errcode, 'error': error}), 400);

    test('a dropped connection keeps the session it had reached', () async {
      final progress = RegistrationProgress();
      final server = serverRunning([
        codeAccepted,
        () => throw http.ClientException('connection lost'),
      ]);

      await expectLater(
        register(server.client, code: 'ABCDEFGH23', progress: progress),
        throwsA(isA<http.ClientException>()),
      );

      expect(progress.session, 'uia1');
      expect(progress.interrupted, isTrue);
    });

    test('a refusal is not an interruption, so a taken username is just '
        'taken', () async {
      final progress = RegistrationProgress();
      final server = serverRunning([() => refused('M_USER_IN_USE')]);

      await expectLater(
        register(server.client, progress: progress),
        throwsA(isA<MatrixException>()),
      );

      expect(progress.interrupted, isFalse);
      expect(server.requests, hasLength(1));
    });

    test('the next attempt resumes that session', () async {
      final progress = RegistrationProgress()..session = 'uia1';
      final server = serverRunning([
        codeAccepted,
        () => refused('M_FORBIDDEN'),
      ]);

      await expectLater(
        register(server.client, code: 'ABCDEFGH23', progress: progress),
        throwsA(isA<MatrixException>()),
      );

      expect(authOf(server.requests.first), {
        'type': 'm.login.registration_token',
        'token': 'ABCDEFGH23',
        'session': 'uia1',
      });
      expect(authOf(server.requests.last), {
        'type': 'm.login.dummy',
        'session': 'uia1',
      });
    });

    test('a resumed session the server forgot is restarted once', () async {
      final progress = RegistrationProgress()..session = 'gone';
      final server = serverRunning([
        () => refused('M_UNKNOWN', 'Unknown session ID: gone'),
        () => refused('M_FORBIDDEN'),
      ]);

      await expectLater(
        register(server.client, code: 'ABCDEFGH23', progress: progress),
        throwsA(isA<MatrixException>()),
      );

      expect(server.requests, hasLength(2));
      expect(authOf(server.requests.last), {
        'type': 'm.login.registration_token',
        'token': 'ABCDEFGH23',
      });
      expect(progress.session, isNull);
    });

    test(
      'a rate limit on a resumed session is not a reason to restart',
      () async {
        final progress = RegistrationProgress()..session = 'uia1';
        final server = serverRunning([() => refused('M_LIMIT_EXCEEDED')]);

        await expectLater(
          register(server.client, code: 'ABCDEFGH23', progress: progress),
          throwsA(isA<MatrixException>()),
        );

        expect(server.requests, hasLength(1));
        expect(progress.session, 'uia1');
      },
    );

    test(
      'a taken username after an interruption tries signing in with it',
      () async {
        final progress = RegistrationProgress()..interrupted = true;
        final server = serverRunning([
          () => refused('M_USER_IN_USE'),
          () => refused('M_FORBIDDEN'),
        ]);

        await expectLater(
          register(server.client, progress: progress),
          throwsA(
            isA<MatrixException>().having(
              (e) => e.error,
              'error',
              MatrixError.M_USER_IN_USE,
            ),
          ),
        );

        expect(server.requests.last.url.path, endsWith('/login'));
        final login =
            jsonDecode(server.requests.last.body) as Map<String, Object?>;
        expect(login['identifier'], {'type': 'm.id.user', 'user': 'alice'});
        expect(login['password'], 'correct horse battery staple');
        expect(login['refresh_token'], isTrue);
        expect(login['initial_device_display_name'], 'Zuno on Android');
      },
    );

    test('sends the code stage first, then the dummy stage', () async {
      final server = serverAnswering([
        uia({
          'session': 'uia1',
          'completed': ['m.login.registration_token'],
          'flows': tokenThenDummyFlows,
        }),
        http.Response(jsonEncode({'errcode': 'M_FORBIDDEN'}), 403),
      ]);

      await expectLater(
        register(server.client, code: 'ABCDEFGH23'),
        throwsA(isA<MatrixException>()),
      );

      expect(authOf(server.requests.first), {
        'type': 'm.login.registration_token',
        'token': 'ABCDEFGH23',
      });
      expect(authOf(server.requests.last), {
        'type': 'm.login.dummy',
        'session': 'uia1',
      });
    });

    test('every register request asks for a refresh token and names the '
        'device', () async {
      final server = serverAnswering([codeAccepted(), refused('M_FORBIDDEN')]);

      await expectLater(
        register(server.client, code: 'ABCDEFGH23'),
        throwsA(isA<MatrixException>()),
      );

      expect(server.requests, hasLength(2));
      for (final request in server.requests) {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        expect(body['refresh_token'], isTrue);
        expect(body['initial_device_display_name'], 'Zuno on Android');
      }
    });

    test(
      'a code the server checks and rejects is reported as refused',
      () async {
        final server = serverAnswering([
          uia({
            'session': 'uia1',
            'completed': <String>[],
            'errcode': 'M_MISSING_PARAM',
            'error': 'Missing UIA session',
            'flows': tokenThenDummyFlows,
          }),
          uia({
            'session': 'uia1',
            'completed': <String>[],
            'errcode': 'M_UNAUTHORIZED',
            'error': 'Invalid registration token',
            'flows': tokenThenDummyFlows,
          }),
        ]);

        await expectLater(
          register(server.client, code: 'ABCDEFGH23'),
          throwsA(isA<RegistrationCodeRefusedException>()),
        );

        expect(server.requests, hasLength(2));
        expect(authOf(server.requests.first), {
          'type': 'm.login.registration_token',
          'token': 'ABCDEFGH23',
        });
        expect(authOf(server.requests.last), {
          'type': 'm.login.registration_token',
          'token': 'ABCDEFGH23',
          'session': 'uia1',
        });
      },
    );

    test(
      'a session-less refusal is retried before the code is blamed',
      () async {
        final server = serverAnswering([
          uia({
            'session': 'uia1',
            'completed': <String>[],
            'errcode': 'M_MISSING_PARAM',
            'error': 'Missing UIA session',
            'flows': tokenThenDummyFlows,
          }),
          uia({
            'session': 'uia1',
            'completed': ['m.login.registration_token'],
            'flows': tokenThenDummyFlows,
          }),
          http.Response(jsonEncode({'errcode': 'M_FORBIDDEN'}), 403),
        ]);

        await expectLater(
          register(server.client, code: 'ABCDEFGH23'),
          throwsA(isA<MatrixException>()),
        );

        expect(server.requests, hasLength(3));
        expect(authOf(server.requests.last), {
          'type': 'm.login.dummy',
          'session': 'uia1',
        });
      },
    );

    test('a flow it cannot walk surfaces the server error', () async {
      final unwalkable = uia({
        'session': 'uia1',
        'completed': <String>[],
        'flows': [
          {
            'stages': ['m.login.recaptcha'],
          },
        ],
      });
      final server = serverAnswering([unwalkable, unwalkable]);

      await expectLater(
        register(server.client),
        throwsA(isA<MatrixException>()),
      );

      expect(server.requests, hasLength(2));
    });

    test(
      'a session the server disowns is restarted once, without one',
      () async {
        final server = serverAnswering([
          uia({
            'session': 'uia1',
            'completed': ['m.login.registration_token'],
            'flows': [
              {
                'stages': ['m.login.registration_token', 'm.login.dummy'],
              },
            ],
          }),
          http.Response(
            jsonEncode({
              'errcode': 'M_FORBIDDEN',
              'error': 'Requested operation has changed during the UI authentication session.',
            }),
            403,
          ),
          http.Response(jsonEncode({'errcode': 'M_FORBIDDEN'}), 403),
        ]);

        await expectLater(
          register(server.client, code: 'ABCDEFGH23'),
          throwsA(isA<MatrixException>()),
        );

        expect(server.requests, hasLength(3));
        expect(authOf(server.requests[1]), {
          'type': 'm.login.dummy',
          'session': 'uia1',
        });
        expect(authOf(server.requests[2]), {
          'type': 'm.login.registration_token',
          'token': 'ABCDEFGH23',
        });
      },
    );
  });

  group('initialRegistrationAuth', () {
    test('starts with the code stage when there is a code', () {
      final auth = initialRegistrationAuth('ABCDEFGH23');

      expect(auth.type, 'm.login.registration_token');
      expect(auth.session, isNull);
      expect(auth.toJson()['token'], 'ABCDEFGH23');
    });

    test('starts with the dummy stage when there is none', () {
      expect(initialRegistrationAuth(null).type, 'm.login.dummy');
    });
  });
}
