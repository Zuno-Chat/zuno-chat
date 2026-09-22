import 'dart:async';
import 'dart:convert';
import 'dart:io' show HandshakeException;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/homeserver.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/matrix/registration_support.dart';

import '../../helpers/fake_matrix.dart';
import '../../helpers/fixed_homeserver.dart';

void main() {
  group('registrationSupportFrom', () {
    test('a 401 offering a dummy-only flow means registration is open', () {
      final support = registrationSupportFrom(401, {
        'session': 'uia1',
        'flows': [
          {
            'stages': ['m.login.dummy'],
          },
        ],
      });

      expect(support.availability, RegistrationAvailability.available);
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

    test('a dummy-only flow needs no code', () {
      final support = registrationSupportFrom(401, {
        'flows': [
          {
            'stages': ['m.login.dummy'],
          },
        ],
      });

      expect(support.requiresRegistrationToken, isFalse);
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
    test('POSTs an empty body to the homeserver register endpoint', () async {
      late Uri requested;
      final client = buildTestClient(
        httpClient: MockClient((request) async {
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
      )..homeserver = Uri.parse('https://example.org');

      final support = await fetchRegistrationSupport(client);

      expect(
        requested.toString(),
        'https://example.org/_matrix/client/v3/register',
      );
      expect(support.isAvailable, isTrue);
    });

    test('a network failure is inconclusive rather than thrown', () async {
      final client = buildTestClient(
        httpClient: MockClient(
          (_) async => throw http.ClientException('offline'),
        ),
      )..homeserver = Uri.parse('https://example.org');

      final support = await fetchRegistrationSupport(client);

      expect(support.availability, RegistrationAvailability.unknown);
    });

    test('a TLS failure is inconclusive rather than thrown', () async {
      final client = buildTestClient(
        httpClient: MockClient(
          (_) async => throw const HandshakeException('captive portal'),
        ),
      )..homeserver = Uri.parse('https://example.org');

      expect(
        (await fetchRegistrationSupport(client)).availability,
        RegistrationAvailability.unknown,
      );
    });

    test('a homeserver that never answers is inconclusive', () {
      fakeAsync((async) {
        final client = buildTestClient(
          httpClient: MockClient((_) => Completer<http.Response>().future),
        )..homeserver = Uri.parse('https://example.org');

        RegistrationSupport? support;
        fetchRegistrationSupport(client).then((value) => support = value);
        async.elapse(registrationProbeTimeout);

        expect(support?.availability, RegistrationAvailability.unknown);
      });
    });

    test('a non-JSON body is inconclusive rather than thrown', () async {
      final client = buildTestClient(
        httpClient: MockClient(
          (_) async => http.Response('<html>nope</html>', 401),
        ),
      )..homeserver = Uri.parse('https://example.org');

      expect(
        (await fetchRegistrationSupport(client)).availability,
        RegistrationAvailability.unknown,
      );
    });
  });

  group('registrationSupportProvider', () {
    ProviderContainer containerProbing(
      Future<http.Response> Function(int probe) answer,
    ) {
      var probes = 0;
      final client = buildTestClient(
        httpClient: MockClient((_) => answer(++probes)),
      )..homeserver = Uri.parse('https://example.org');
      final container = ProviderContainer(
        overrides: [
          matrixClientProvider.overrideWithValue(client),
          homeserverProvider.overrideWith(
            () => FixedHomeserver(Uri.parse('https://example.org')),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('an inconclusive probe is tried again', () async {
      final probes = <int>[];
      final container = containerProbing((probe) async {
        probes.add(probe);
        if (probe == 1) throw http.ClientException('offline');
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
      });
      final subscription = container.listen(
        registrationSupportProvider,
        (_, _) {},
      );

      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (subscription.read().value == null &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      expect(probes, [1, 2]);
      expect(subscription.read().value?.isAvailable, isTrue);
    });

    test('a conclusive answer is not asked for twice', () async {
      final probes = <int>[];
      final container = containerProbing((probe) async {
        probes.add(probe);
        return http.Response(jsonEncode({'errcode': 'M_FORBIDDEN'}), 403);
      });
      final subscription = container.listen(
        registrationSupportProvider,
        (_, _) {},
      );

      await container.read(registrationSupportProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(probes, [1]);
      expect(
        subscription.read().value?.availability,
        RegistrationAvailability.disabled,
      );
    });

    test(
      'is dropped with the screen, so another server is asked afresh',
      () async {
        final probes = <int>[];
        final container = containerProbing((probe) async {
          probes.add(probe);
          return http.Response(jsonEncode({'errcode': 'M_FORBIDDEN'}), 403);
        });

        final first = container.listen(registrationSupportProvider, (_, _) {});
        await container.read(registrationSupportProvider.future);
        first.close();
        await container.pump();

        final second = container.listen(registrationSupportProvider, (_, _) {});
        await container.read(registrationSupportProvider.future);
        second.close();

        expect(probes, [1, 2]);
      },
    );
  });

  group('registrationInputError', () {
    String? errorFor({
      String username = 'alex',
      String password = 'correcthorse',
      String? confirmPassword,
    }) => registrationInputError(
      username: username,
      password: password,
      confirmPassword: confirmPassword ?? password,
    );

    test('accepts a plain username and a matching password', () {
      expect(errorFor(), isNull);
    });

    test('rejects a full user ID pasted into the username field', () {
      expect(errorFor(username: '@alex:example.org'), isNotNull);
    });

    test('rejects a too-short password', () {
      expect(errorFor(password: 'short'), isNotNull);
    });

    test('rejects a mismatched confirmation', () {
      expect(errorFor(confirmPassword: 'somethingelse'), isNotNull);
    });

    test(
      'accepts dots and underscores, which people use to separate words',
      () {
        expect(errorFor(username: 'alex.smith'), isNull);
        expect(errorFor(username: 'alex_smith'), isNull);
      },
    );

    test('rejects the separators that survive being spoken least well', () {
      for (final username in ['alex-1', 'a+b', 'a/b', 'a=b']) {
        expect(errorFor(username: username), isNotNull, reason: username);
      }
    });

    test('rejects uppercase, which is not a valid localpart', () {
      expect(errorFor(username: 'Alex'), isNotNull);
    });

    test('accepts letters and digits together', () {
      expect(errorFor(username: 'alex2026'), isNull);
    });

    test('rejects a common password even when it is long enough', () {
      expect(errorFor(password: 'password1234'), isNotNull);
    });

    test('rejects a password that is just the username', () {
      expect(
        errorFor(username: 'alexanderthegreat', password: 'alexanderthegreat'),
        isNotNull,
      );
    });

    test('rejects a leading underscore, which Synapse keeps for bridges', () {
      expect(errorFor(username: '_alex'), contains('underscore'));
      expect(errorFor(username: 'alex_'), isNull);
    });

    test('rejects a username with no letter in it', () {
      for (final username in ['2026', '1_000', '1.5', '...']) {
        expect(errorFor(username: username), contains('letter'));
      }
      expect(errorFor(username: 'a2026'), isNull);
    });

    test('rejects a username too long to fit in a user ID', () {
      String? errorWithServer(int length) => registrationInputError(
        username: 'a' * length,
        password: 'correcthorse',
        confirmPassword: 'correcthorse',
        serverName: 'zuno.chat',
      );

      expect(errorWithServer(244), isNull);
      expect(errorWithServer(245), contains('too long'));
    });

    test('rejects a password longer than the homeserver accepts', () {
      final long = [for (var i = 0; i < 120; i++) 'kestrel$i'].join(' ');

      expect(errorFor(password: long.substring(0, 512)), isNull);
      expect(errorFor(password: long.substring(0, 513)), contains('512'));
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
    ({Client client, List<Map<String, Object?>> bodies}) serverAnswering(
      List<http.Response> responses,
    ) {
      final bodies = <Map<String, Object?>>[];
      final client = buildTestClient(
        httpClient: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, Object?>);
          return responses[bodies.length - 1];
        }),
      )..homeserver = Uri.parse('https://example.org');
      return (client: client, bodies: bodies);
    }

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
        httpClient: MockClient((request) async {
          requests.add(request);
          return answers[requests.length - 1]();
        }),
      )..homeserver = Uri.parse('https://example.org');
      return (client: client, requests: requests);
    }

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

    test('a refusal is not an interruption', () async {
      final progress = RegistrationProgress();
      final server = serverRunning([() => refused('M_USER_IN_USE')]);

      await expectLater(
        register(server.client, progress: progress),
        throwsA(isA<MatrixException>()),
      );

      expect(progress.interrupted, isFalse);
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

    test('a taken username with no interruption is just taken', () async {
      final server = serverRunning([() => refused('M_USER_IN_USE')]);

      await expectLater(
        register(server.client, progress: RegistrationProgress()),
        throwsA(isA<MatrixException>()),
      );

      expect(server.requests, hasLength(1));
    });

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

      expect(server.bodies.first['auth'], {
        'type': 'm.login.registration_token',
        'token': 'ABCDEFGH23',
      });
      expect(server.bodies.last['auth'], {
        'type': 'm.login.dummy',
        'session': 'uia1',
      });
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

        expect(server.bodies, hasLength(2));
        expect(server.bodies.first['auth'], {
          'type': 'm.login.registration_token',
          'token': 'ABCDEFGH23',
        });
        expect(server.bodies.last['auth'], {
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

        expect(server.bodies, hasLength(3));
        expect(server.bodies.last['auth'], {
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

      expect(server.bodies, hasLength(2));
    });

    test(
      'a dummy stage refused without a session is retried with it',
      () async {
        final server = serverAnswering([
          uia({
            'session': 'uia1',
            'completed': <String>[],
            'flows': [
              {
                'stages': ['m.login.dummy'],
              },
            ],
          }),
          http.Response(jsonEncode({'errcode': 'M_FORBIDDEN'}), 403),
        ]);

        await expectLater(
          register(server.client),
          throwsA(isA<MatrixException>()),
        );

        expect(server.bodies, hasLength(2));
        expect(server.bodies.first['auth'], {'type': 'm.login.dummy'});
        expect(server.bodies.last['auth'], {
          'type': 'm.login.dummy',
          'session': 'uia1',
        });
      },
    );

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

        expect(server.bodies, hasLength(3));
        expect(server.bodies[1]['auth'], {
          'type': 'm.login.dummy',
          'session': 'uia1',
        });
        expect(server.bodies[2]['auth'], {
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
