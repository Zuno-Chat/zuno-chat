import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:zuno/core/matrix/registration_support.dart';
import 'package:zuno/core/matrix/server_choice.dart';

import '../../helpers/caught_reports.dart';
import '../../helpers/fake_http.dart';
import '../../helpers/fake_matrix.dart';

void main() {
  group('signUpPathFrom', () {
    const open = RegistrationSupport(RegistrationAvailability.available);
    const needsCode = RegistrationSupport(
      RegistrationAvailability.available,
      requiresRegistrationToken: true,
    );

    test('a flow without a code is open', () {
      expect(signUpPathFrom(open, mailsSignUpCodes: null), SignUpPath.open);
    });

    test('a code from a server announcing zuno_register is emailed', () {
      expect(
        signUpPathFrom(needsCode, mailsSignUpCodes: true),
        SignUpPath.emailedCode,
      );
    });

    test('a code from a server announcing nothing comes from its admin', () {
      expect(
        signUpPathFrom(needsCode, mailsSignUpCodes: false),
        SignUpPath.adminCode,
      );
    });

    test('a code from a server whose announcement is unknown is unknown', () {
      expect(
        signUpPathFrom(needsCode, mailsSignUpCodes: null),
        SignUpPath.unknown,
      );
    });

    for (final availability in [
      RegistrationAvailability.disabled,
      RegistrationAvailability.unsupportedFlow,
    ]) {
      test('${availability.name} is closed whatever the announcement', () {
        for (final mails in [true, false, null]) {
          expect(
            signUpPathFrom(
              RegistrationSupport(availability),
              mailsSignUpCodes: mails,
            ),
            SignUpPath.closed,
            reason: '$mails',
          );
        }
      });
    }

    test('an inconclusive probe is unknown', () {
      expect(
        signUpPathFrom(
          const RegistrationSupport(RegistrationAvailability.unknown),
          mailsSignUpCodes: true,
        ),
        SignUpPath.unknown,
      );
    });
  });

  group('readDiscovery', () {
    final server = Uri.parse('https://example.org');

    Future<({Uri? homeserver, bool? mailsSignUpCodes})> discover(
      FakeHttpHandler answer, {
      List<Uri>? requested,
    }) => readDiscovery(
      buildTestClient(
        httpClient: FakeHttpClient((request) {
          requested?.add(request.url);
          return answer(request);
        }),
      ),
      server,
    );

    http.Response json(Object? body) => http.Response(jsonEncode(body), 200);

    test(
      'a discovery file naming the API host and announcing zuno_register',
      () async {
        final requested = <Uri>[];

        final discovered = await discover(
          (_) async => json({
            'm.homeserver': {'base_url': 'https://api.example.org'},
            'chat.zuno.register': <String, Object?>{},
          }),
          requested: requested,
        );

        expect(discovered, (
          homeserver: Uri.parse('https://api.example.org'),
          mailsSignUpCodes: true,
        ));
        expect(requested, [
          Uri.parse('https://example.org/.well-known/matrix/client'),
        ]);
      },
    );

    test('a discovery file without the key announces nothing', () async {
      final discovered = await discover(
        (_) async => json({
          'm.homeserver': {'base_url': 'https://api.example.org'},
        }),
      );

      expect(discovered, (
        homeserver: Uri.parse('https://api.example.org'),
        mailsSignUpCodes: false,
      ));
    });

    test('a key that is not an object announces nothing', () async {
      final discovered = await discover(
        (_) async => json({
          'm.homeserver': {'base_url': 'https://api.example.org'},
          'chat.zuno.register': true,
        }),
      );

      expect(discovered.mailsSignUpCodes, isFalse);
    });

    test('a missing file announces nothing', () async {
      final discovered = await discover(
        (_) async => http.Response(jsonEncode({'errcode': 'M_NOT_FOUND'}), 404),
      );

      expect(discovered, (homeserver: null, mailsSignUpCodes: false));
    });

    test('a web page served as the discovery file announces nothing', () async {
      final discovered = await discover(
        (_) async => http.Response(
          '<html><body>Welcome to example.org</body></html>',
          200,
        ),
      );

      expect(discovered, (homeserver: null, mailsSignUpCodes: false));
    });

    test('a discovery file without m.homeserver announces nothing', () async {
      final discovered = await discover(
        (_) async => json(<String, Object?>{'chat.zuno.register': {}}),
      );

      expect(discovered, (homeserver: null, mailsSignUpCodes: false));
    });

    test(
      'an unreachable discovery file leaves the announcement unknown',
      () async {
        late ({Uri? homeserver, bool? mailsSignUpCodes}) discovered;
        final reports = await reportsDuring(
          () async => discovered = await discover(
            (_) async => throw http.ClientException('offline'),
          ),
        );

        expect(discovered, (homeserver: null, mailsSignUpCodes: null));
        expect(reports, isEmpty);
      },
    );

    test('a server error leaves the announcement unknown', () async {
      final discovered = await discover((_) async => http.Response('', 503));

      expect(discovered, (homeserver: null, mailsSignUpCodes: null));
    });

    test(
      'a rate-limited discovery file leaves the announcement unknown',
      () async {
        final discovered = await discover((_) async => http.Response('', 429));

        expect(discovered, (homeserver: null, mailsSignUpCodes: null));
      },
    );

    test('a base_url without a scheme announces nothing', () async {
      final discovered = await discover(
        (_) async => json({
          'm.homeserver': {'base_url': 'matrix.example.org'},
          'chat.zuno.register': <String, Object?>{},
        }),
      );

      expect(discovered, (homeserver: null, mailsSignUpCodes: false));
    });

    test('a base_url that is not http or https announces nothing', () async {
      final discovered = await discover(
        (_) async => json({
          'm.homeserver': {'base_url': 'ftp://matrix.example.org'},
          'chat.zuno.register': <String, Object?>{},
        }),
      );

      expect(discovered, (homeserver: null, mailsSignUpCodes: false));
    });

    test('a base_url that is not a URL announces nothing', () async {
      for (final base in <Object?>['https://[bad', 42]) {
        final discovered = await discover(
          (_) async => json({
            'm.homeserver': {'base_url': base},
            'chat.zuno.register': <String, Object?>{},
          }),
        );

        expect(discovered, (
          homeserver: null,
          mailsSignUpCodes: false,
        ), reason: '$base');
      }
    });

    test(
      'an odd failure is reported and leaves the announcement unknown',
      () async {
        late ({Uri? homeserver, bool? mailsSignUpCodes}) discovered;
        final reports = await reportsDuring(
          () async => discovered = await discover(
            (_) async => throw Exception('closed'),
          ),
        );

        expect(discovered, (homeserver: null, mailsSignUpCodes: null));
        expect(reports, ['read discovery file']);
      },
    );

    test('a bug while reading the discovery file is not hidden', () async {
      await expectLater(
        discover((_) async => throw StateError('bug')),
        throwsStateError,
      );
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
      ServerChoice(server, apiHost: apiHost, mailsSignUpCodes: null),
    ]) {
      expect(choice, isNot(other));
    }
  });
}
