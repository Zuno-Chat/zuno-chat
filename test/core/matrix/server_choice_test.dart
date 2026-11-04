import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/errors/connection_error.dart';
import 'package:zuno/core/matrix/auth_error_message.dart';
import 'package:zuno/core/matrix/homeserver.dart';
import 'package:zuno/core/matrix/registration_support.dart';
import 'package:zuno/core/matrix/server_choice.dart';

import '../../helpers/caught_reports.dart';
import '../../helpers/fake_http.dart';
import '../../helpers/fake_matrix.dart';

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
    final requests = <Uri>[];

    setUp(requests.clear);

    http.Response json(Object? body, [int status = 200]) =>
        http.Response(jsonEncode(body), status);

    http.Response notFound() => json({'errcode': 'M_NOT_FOUND'}, 404);

    http.Response discoveryNaming(Object? base) => json({
      'm.homeserver': {'base_url': base},
    });

    Client clientAnswering({
      FakeHttpHandler? discovery,
      FakeHttpHandler? versions,
      FakeHttpHandler? login,
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
          _ => notFound(),
        };
      }),
    );

    List<Uri> requestsTo(String path) =>
        requests.where((url) => url.path == path).toList();

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
        Uri.parse('https://matrix.example.org$loginPath'),
      ]);
    });

    test('sign-in methods are asked for without waiting on versions', () async {
      final versions = Completer<http.Response>();
      final client = clientAnswering(versions: (_) => versions.future);

      final checked = checkServer(client, server);
      await pumpEventQueue();

      expect(requestsTo(loginPath), hasLength(1));
      versions.complete(
        json({
          'versions': ['v1.5'],
        }),
      );
      expect(await checked, ServerChoice(server, apiHost: server));
    });

    test('a server that is not Matrix fails as not Matrix even when its '
        'sign-in methods are unreachable', () async {
      final client = clientAnswering(
        versions: (_) async => http.Response('<html></html>', 404),
        login: (_) async => throw http.ClientException('offline'),
      );

      final error = await checkServer(
        client,
        server,
      ).then<Object?>((_) => null, onError: (Object e) => e);

      expect(error, isNotNull);
      expect(isNotMatrixAnswer(error!), isTrue);
    });

    test(
      'auth metadata is never requested, even from a v1.15 server',
      () async {
        final client = clientAnswering(
          versions: (_) async => json({
            'versions': ['v1.15'],
          }),
        );

        await checkServer(client, server);

        expect(requestsTo('/_matrix/client/v1/auth_metadata'), isEmpty);
      },
    );

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
          throwsA(
            predicate(
              (Object error) =>
                  homeserverProblem(error) == HomeserverProblem.notAServer,
            ),
          ),
        );
      },
    );

    test('a server without password sign-in is refused', () async {
      final client = clientAnswering(
        login: (_) async => json({
          'flows': [
            {'type': 'm.login.sso'},
          ],
        }),
      );

      await expectLater(
        checkServer(client, server),
        throwsA(
          isA<BadServerLoginTypesException>().having(
            (error) => error.serverLoginTypes,
            'server types',
            {'m.login.sso'},
          ),
        ),
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

    expect(choice, ServerChoice(server, apiHost: apiHost));
    expect(choice.hashCode, ServerChoice(server, apiHost: apiHost).hashCode);
    for (final other in [
      ServerChoice(apiHost, apiHost: apiHost),
      ServerChoice(server, apiHost: server),
    ]) {
      expect(choice, isNot(other));
    }
  });
}
