import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/auth/auth_error_message.dart';
import 'package:zuno/core/matrix/auth/homeserver.dart';
import 'package:zuno/core/matrix/auth/registration_support.dart';
import 'package:zuno/core/matrix/auth/server_choice.dart';
import 'package:zuno/core/matrix/http/typed_server_answers.dart';

import '../../../helpers/caught_reports.dart';
import '../../../helpers/fake_http.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/oauth_server.dart';

void main() {
  group('signUpPathFrom', () {
    test('a flow without a code is open', () {
      expect(
        signUpPathFrom(
          const RegistrationSupport(RegistrationAvailability.available),
        ),
        SignUpPath.open,
      );
    });

    test('a code needed by every flow signs up with a code', () {
      expect(
        signUpPathFrom(
          const RegistrationSupport(
            RegistrationAvailability.available,
            requiresRegistrationToken: true,
          ),
        ),
        SignUpPath.code,
      );
    });

    for (final availability in [
      RegistrationAvailability.disabled,
      RegistrationAvailability.unsupportedFlow,
    ]) {
      test('${availability.name} is closed', () {
        expect(
          signUpPathFrom(RegistrationSupport(availability)),
          SignUpPath.closed,
        );
      });
    }

    test('an inconclusive probe is unknown', () {
      expect(
        signUpPathFrom(
          const RegistrationSupport(RegistrationAvailability.unknown),
        ),
        SignUpPath.unknown,
      );
    });
  });

  group('checkServer', () {
    final server = Uri.parse('https://example.org');
    const discoveryPath = '/.well-known/matrix/client';
    const versionsPath = '/_matrix/client/versions';
    const loginPath = '/_matrix/client/v3/login';
    const metadataPath = '/_matrix/client/v1/auth_metadata';
    final requests = <Uri>[];

    setUp(requests.clear);

    http.Response json(Object? body, [int status = 200]) =>
        http.Response(jsonEncode(body), status);

    http.Response notFound() => json({'errcode': 'M_NOT_FOUND'}, 404);

    http.Response discoveryNaming(Object? base) => json({
      'm.homeserver': {'base_url': base},
    });

    http.Response metadataWith(Map<String, Object?> fields) =>
        json({...oauthMetadata, ...fields});

    http.Response loginTypes(List<String> types) => json({
      'flows': [
        for (final type in types) {'type': type},
      ],
    });

    Client clientAnswering({
      FakeHttpHandler? discovery,
      FakeHttpHandler? versions,
      FakeHttpHandler? login,
      FakeHttpHandler? metadata,
    }) => buildTestClient(
      httpClient: FakeHttpClient((request) async {
        requests.add(request.url);
        return switch (request.url.path) {
          discoveryPath => discovery == null ? notFound() : discovery(request),
          versionsPath =>
            versions == null
                ? json({
                    'versions': ['v1.5', 'v1.15'],
                  })
                : versions(request),
          loginPath =>
            login == null
                ? json({
                    'flows': [
                      {'type': 'm.login.password'},
                    ],
                  })
                : login(request),
          metadataPath => metadata == null ? notFound() : metadata(request),
          _ => notFound(),
        };
      }),
    );

    List<Uri> requestsTo(String path) =>
        requests.where((url) => url.path == path).toList();

    Matcher throwsProblem(HomeserverProblem problem) => throwsA(
      predicate(
        (Object error) => homeserverProblem(error) == problem,
        problem.name,
      ),
    );

    test('a discovery file naming another API host points the check '
        'there', () async {
      final client = clientAnswering(
        discovery: (_) async => discoveryNaming('https://matrix.example.org/'),
      );

      final choice = await checkServer(client, server);

      expect(
        choice,
        ServerChoice(server, apiHost: Uri.parse('https://matrix.example.org')),
      );
      expect(requests, [
        Uri.parse('https://example.org$discoveryPath'),
        Uri.parse('https://matrix.example.org$versionsPath'),
        Uri.parse('https://matrix.example.org$metadataPath'),
        Uri.parse('https://matrix.example.org$loginPath'),
      ]);
    });

    test('sign-in methods and auth metadata are asked for without waiting on '
        'versions', () async {
      final versions = Completer<http.Response>();
      final client = clientAnswering(versions: (_) => versions.future);

      final checked = checkServer(client, server);
      await pumpEventQueue();

      expect(requestsTo(loginPath), hasLength(1));
      expect(requestsTo(metadataPath), hasLength(1));
      versions.complete(
        json({
          'versions': ['v1.5'],
        }),
      );
      expect(await checked, ServerChoice(server, apiHost: server));
    });

    test('a server that is not Matrix fails as not Matrix even when its '
        'sign-in methods and auth metadata are unreachable', () async {
      final client = clientAnswering(
        versions: (_) async => http.Response('<html></html>', 404),
        login: (_) async => throw http.ClientException('offline'),
        metadata: (_) async => throw http.ClientException('offline'),
      );

      await expectLater(
        checkServer(client, server),
        throwsProblem(HomeserverProblem.notAServer),
      );
    });

    test('a v1.15 server serving auth metadata signs in through OAuth, '
        'asked once at its API host', () async {
      final apiHost = Uri.parse('https://matrix.example.org');
      final client = clientAnswering(
        discovery: (_) async => discoveryNaming('$apiHost'),
        versions: (_) async => json({
          'versions': ['v1.15'],
        }),
        login: (_) async => loginTypes(['m.login.sso']),
        metadata: (_) async => json(oauthMetadata),
      )..homeserver = officialHomeserver;

      final choice = await checkServer(client, server);

      expect(
        choice,
        ServerChoice(
          server,
          apiHost: apiHost,
          signIn: const OAuthSignIn(canCreateAccount: true),
        ),
      );
      expect(requestsTo(metadataPath), [
        Uri.parse('https://matrix.example.org$metadataPath'),
      ]);
    });

    test('auth metadata wins over password sign-in', () async {
      final client = clientAnswering(
        login: (_) async => loginTypes(['m.login.password', 'm.login.sso']),
        metadata: (_) async => json(oauthMetadata),
      );

      expect((await checkServer(client, server)).signIn, isA<OAuthSignIn>());
    });

    for (final (name, answer) in <(String, FakeHttpHandler)>[
      (
        'a server error',
        (_) async => http.Response('<html>Bad Gateway</html>', 502),
      ),
      (
        'a web page for a missing endpoint',
        (_) async => http.Response('<html>Not Found</html>', 404),
      ),
      ('no answer at all', (_) => Completer<http.Response>().future),
    ]) {
      test('a server serving auth metadata signs in through OAuth when its '
          'sign-in methods meet $name', () async {
        final client = clientAnswering(
          login: answer,
          metadata: (_) async => json(oauthMetadata),
        );

        expect(
          await checkServer(client, server),
          ServerChoice(
            server,
            apiHost: server,
            signIn: const OAuthSignIn(canCreateAccount: true),
          ),
        );
      });
    }

    test(
      'OAuth can create accounts only where the server offers create',
      () async {
        for (final (prompts, canCreate) in <(List<String>?, bool)>[
          (['login', 'create'], true),
          (['login'], false),
          (null, false),
        ]) {
          final client = clientAnswering(
            metadata: (_) async =>
                metadataWith({'prompt_values_supported': prompts}),
          );

          final choice = await checkServer(client, server);

          expect(
            choice.signIn,
            OAuthSignIn(canCreateAccount: canCreate),
            reason: '$prompts',
          );
        }
      },
    );

    for (final (name, answer) in <(String, FakeHttpHandler)>[
      ('a missing endpoint', (_) async => notFound()),
      (
        'a proxy web page for a missing endpoint',
        (_) async => http.Response('<html>Not Found</html>', 404),
      ),
      (
        'M_UNRECOGNIZED on another status',
        (_) async => json({'errcode': 'M_UNRECOGNIZED'}, 400),
      ),
      (
        'M_NOT_FOUND on another status',
        (_) async => json({'errcode': 'M_NOT_FOUND'}, 400),
      ),
    ]) {
      test('$name means password sign-in', () async {
        final client = clientAnswering(metadata: answer);

        expect(
          await checkServer(client, server),
          ServerChoice(server, apiHost: server),
        );
      });
    }

    for (final status in [403, 429, 502]) {
      test('a $status auth metadata answer fails the check', () async {
        final client = clientAnswering(
          metadata: (_) async => http.Response('', status),
        );

        await expectLater(
          checkServer(client, server),
          throwsA(
            isA<ServerAnswerFailed>().having(
              (error) => error.statusCode,
              'status',
              status,
            ),
          ),
        );
      });
    }

    test('a server error page served as auth metadata fails the check as '
        'unreachable, not as a password server', () async {
      final client = clientAnswering(
        metadata: (_) async => http.Response('<html>Bad Gateway</html>', 502),
      );

      await expectLater(
        checkServer(client, server),
        throwsProblem(HomeserverProblem.unreachable),
      );
    });

    test('a Matrix refusal of auth metadata fails the check', () async {
      final client = clientAnswering(
        metadata: (_) async => json({'errcode': 'M_FORBIDDEN'}, 403),
      );

      await expectLater(
        checkServer(client, server),
        throwsA(isA<MatrixException>()),
      );
    });

    for (final (name, answer) in <(String, FakeHttpHandler)>[
      (
        'auth metadata missing a required field',
        (_) async => json({...oauthMetadata}..remove('revocation_endpoint')),
      ),
      (
        'a web page served as auth metadata',
        (_) async => http.Response('<html><body>Welcome</body></html>', 200),
      ),
      ('auth metadata that is not an object', (_) async => json(['issuer'])),
    ]) {
      test('$name fails the check as not a server', () async {
        final client = clientAnswering(metadata: answer);

        await expectLater(
          checkServer(client, server),
          throwsProblem(HomeserverProblem.notAServer),
        );
      });
    }

    test('auth metadata that cannot be fetched fails the check', () async {
      final client = clientAnswering(
        metadata: (_) async => throw http.ClientException('offline'),
      );

      await expectLater(
        checkServer(client, server),
        throwsA(isA<http.ClientException>()),
      );
    });

    test('a failed auth metadata answer wins over unreachable sign-in '
        'methods', () async {
      final client = clientAnswering(
        metadata: (_) async => http.Response('', 502),
        login: (_) async => throw http.ClientException('offline'),
      );

      await expectLater(
        checkServer(client, server),
        throwsA(isA<ServerAnswerFailed>()),
      );
    });

    for (final (name, answer) in <(String, FakeHttpHandler)>[
      ('a missing file', (_) async => notFound()),
      (
        'a missing file served as a web page',
        (_) async => http.Response('<html><body>Not found</body></html>', 404),
      ),
      (
        'a web page served as the discovery file',
        (_) async => http.Response('<html><body>Welcome</body></html>', 200),
      ),
      ('a server error', (_) async => http.Response('', 503)),
      ('a rate limit', (_) async => http.Response('', 429)),
      (
        'an unreachable file',
        (_) async => throw http.ClientException('offline'),
      ),
      (
        'a base_url without a scheme',
        (_) async => discoveryNaming('matrix.example.org'),
      ),
      (
        'a base_url that is not http or https',
        (_) async => discoveryNaming('ftp://matrix.example.org'),
      ),
      (
        'a base_url without a host',
        (_) async => discoveryNaming('https:///matrix'),
      ),
      (
        'a base_url that is not a URL',
        (_) async => discoveryNaming('https://[bad'),
      ),
      ('a base_url that is not text', (_) async => discoveryNaming(42)),
      ('a file without m.homeserver', (_) async => json(<String, Object?>{})),
      ('a file that is not an object', (_) async => json(['m.homeserver'])),
    ]) {
      test(
        '$name leaves the typed server as the API host, unreported',
        () async {
          final client = clientAnswering(discovery: answer);

          late ServerChoice choice;
          final reports = await reportsDuring(
            () async => choice = await checkServer(client, server),
          );

          expect(choice, ServerChoice(server, apiHost: server));
          expect(requestsTo(versionsPath).single.host, 'example.org');
          expect(reports, isEmpty);
        },
      );
    }

    test(
      'the typed server is the API host without its trailing slash',
      () async {
        final typed = Uri.parse('https://example.org/');

        final choice = await checkServer(clientAnswering(), typed);

        expect(choice, ServerChoice(typed, apiHost: server));
      },
    );

    test('an odd discovery failure is reported and the typed server is the '
        'API host', () async {
      final client = clientAnswering(
        discovery: (_) async => throw Exception('closed'),
      );

      late ServerChoice choice;
      final reports = await reportsDuring(
        () async => choice = await checkServer(client, server),
      );

      expect(choice, ServerChoice(server, apiHost: server));
      expect(reports, ['read discovery file']);
    });

    test('a bug while reading the discovery file is not hidden', () async {
      final client = clientAnswering(
        discovery: (_) async => throw StateError('bug'),
      );

      await expectLater(checkServer(client, server), throwsStateError);
    });

    test('a server that does not answer fails the check', () async {
      final client = clientAnswering(
        versions: (_) async => throw http.ClientException('offline'),
      );

      await expectLater(
        checkServer(client, server),
        throwsA(isA<http.ClientException>()),
      );
    });

    test(
      'an address that is not a Matrix server fails the check as one',
      () async {
        final client = clientAnswering(
          versions: (_) async => http.Response('<html></html>', 404),
        );

        await expectLater(
          checkServer(client, server),
          throwsProblem(HomeserverProblem.notAServer),
        );
      },
    );

    for (final (name, answer, problem)
        in <(String, http.Response, HomeserverProblem)>[
          (
            'a 429 on versions says rate limited',
            http.Response('<html>Too Many Requests</html>', 429),
            HomeserverProblem.rateLimited,
          ),
          (
            'a rate limit refusal on versions says rate limited',
            json({'errcode': 'M_LIMIT_EXCEEDED', 'retry_after_ms': 30000}, 429),
            HomeserverProblem.rateLimited,
          ),
          (
            'a 502 on versions says unreachable',
            http.Response('<html>Bad Gateway</html>', 502),
            HomeserverProblem.unreachable,
          ),
        ]) {
      test(name, () async {
        final client = clientAnswering(versions: (_) async => answer);

        await expectLater(checkServer(client, server), throwsProblem(problem));
      });
    }

    test('a server error on the sign-in methods fails the check as '
        'unreachable', () async {
      final client = clientAnswering(
        login: (_) async => http.Response('<html>Bad Gateway</html>', 502),
      );

      await expectLater(
        checkServer(client, server),
        throwsProblem(HomeserverProblem.unreachable),
      );
    });

    test('a server with neither password sign-in nor auth metadata is '
        'refused', () async {
      final client = clientAnswering(
        login: (_) async => loginTypes(['m.login.sso']),
      );

      await expectLater(
        checkServer(client, server),
        throwsA(isA<UnsupportedSignInException>()),
      );
    });

    test('an empty sign-in method list counts as password sign-in', () async {
      final client = clientAnswering(login: (_) async => loginTypes([]));

      expect(
        await checkServer(client, server),
        ServerChoice(server, apiHost: server),
      );
    });

    test('a refused sign-in method list counts as none', () async {
      final client = clientAnswering(
        login: (_) async => json({'errcode': 'M_UNRECOGNIZED'}, 404),
      );

      expect(
        await checkServer(client, server),
        ServerChoice(server, apiHost: server),
      );
    });

    test(
      'a sign-in method list that cannot be fetched fails the check',
      () async {
        final client = clientAnswering(
          login: (_) async => throw http.ClientException('offline'),
        );

        await expectLater(
          checkServer(client, server),
          throwsA(isA<http.ClientException>()),
        );
      },
    );

    test('a check leaves the client where it was, passed or failed', () async {
      var online = true;
      final client = clientAnswering(
        versions: (_) async => online
            ? json({
                'versions': ['v1.5'],
              })
            : throw http.ClientException('offline'),
      )..homeserver = officialHomeserver;

      await checkServer(client, server);
      expect(client.homeserver, officialHomeserver);

      online = false;
      await expectLater(
        checkServer(client, server),
        throwsA(isA<http.ClientException>()),
      );
      expect(client.homeserver, officialHomeserver);
    });
  });

  test('two choices are equal only when every field is', () {
    final server = Uri.parse('https://example.org');
    final apiHost = Uri.parse('https://matrix.example.org');
    final choice = ServerChoice(server, apiHost: apiHost);
    ServerChoice oauth({required bool canCreate}) => ServerChoice(
      server,
      apiHost: apiHost,
      signIn: OAuthSignIn(canCreateAccount: canCreate),
    );

    expect(choice, ServerChoice(server, apiHost: apiHost));
    expect(choice.hashCode, ServerChoice(server, apiHost: apiHost).hashCode);
    expect(oauth(canCreate: true), oauth(canCreate: true));
    expect(oauth(canCreate: true).hashCode, oauth(canCreate: true).hashCode);
    for (final other in [
      ServerChoice(apiHost, apiHost: apiHost),
      ServerChoice(server, apiHost: server),
      oauth(canCreate: false),
      oauth(canCreate: true),
    ]) {
      expect(choice, isNot(other));
    }
    expect(oauth(canCreate: true), isNot(oauth(canCreate: false)));
  });
}
