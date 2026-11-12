import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/client/zuno_client.dart';
import 'package:zuno/core/matrix/http/typed_server_answers.dart';

import '../../../helpers/caught_reports.dart';
import '../../../helpers/fake_http.dart';
import '../../../helpers/fake_matrix.dart';

class _Api extends MatrixApi with TypedServerAnswers {}

void main() {
  Never answer(http.Response response) =>
      _Api().unexpectedResponse(response, response.bodyBytes);

  http.Response json(Object? body, int status) =>
      http.Response(jsonEncode(body), status);

  Matcher failedWith(int status, {String? oauthError}) => throwsA(
    isA<ServerAnswerFailed>()
        .having((e) => e.statusCode, 'status', status)
        .having((e) => e.oauthError, 'oauthError', oauthError),
  );

  test('a Matrix error is the SDK’s MatrixException', () {
    expect(
      () => answer(json({'errcode': 'M_FORBIDDEN', 'error': 'No'}, 403)),
      throwsA(
        isA<MatrixException>().having(
          (e) => e.error,
          'error',
          MatrixError.M_FORBIDDEN,
        ),
      ),
    );
  });

  test('a sign-in challenge is still the SDK’s MatrixException', () {
    expect(
      () => answer(
        json({
          'session': 's1',
          'flows': [
            {
              'stages': ['m.login.password'],
            },
          ],
        }, 401),
      ),
      throwsA(isA<MatrixException>().having((e) => e.session, 'session', 's1')),
    );
  });

  test('a web page carries its status', () {
    expect(
      () => answer(http.Response('<html>Bad Gateway</html>', 502)),
      failedWith(502),
    );
  });

  test('an OAuth error carries its code', () {
    expect(
      () => answer(
        json({
          'error': 'invalid_client_metadata',
          'error_description': 'redirect_uris is invalid',
        }, 400),
      ),
      failedWith(400, oauthError: 'invalid_client_metadata'),
    );
  });

  for (final (name, body) in <(String, Object?)>[
    ('an error that is not a code', {'error': 5}),
    ('JSON that is not an object', ['invalid_client_metadata']),
    ('an empty answer', null),
  ]) {
    test('$name carries only its status', () {
      expect(
        () => answer(body == null ? http.Response('', 400) : json(body, 400)),
        failedWith(400),
      );
    });
  }

  test('keeps a Retry-After in seconds', () {
    for (final (header, wait) in <(String?, Duration?)>[
      ('30', const Duration(seconds: 30)),
      ('Wed, 04 Nov 2026 10:00:00 GMT', null),
      (null, null),
    ]) {
      expect(
        () => answer(
          http.Response(
            '<html>Too Many Requests</html>',
            429,
            headers: {'retry-after': ?header},
          ),
        ),
        throwsA(
          isA<ServerAnswerFailed>().having(
            (e) => e.retryAfter,
            'retryAfter',
            wait,
          ),
        ),
        reason: header,
      );
    }
  });

  test('names the code, when there is one, after the status', () {
    expect(
      const ServerAnswerFailed(
        400,
        oauthError: 'invalid_client_metadata',
      ).toString(),
      'ServerAnswerFailed(400, invalid_client_metadata)',
    );
    expect(const ServerAnswerFailed(502).toString(), 'ServerAnswerFailed(502)');
  });

  test('no connection, a rate limit and a server error are expected; any '
      'other answer is not', () {
    for (final error in <Object>[
      const SocketException('down'),
      MatrixException.fromJson({'errcode': 'M_LIMIT_EXCEEDED'}),
      const ServerAnswerFailed(429),
      const ServerAnswerFailed(500),
      const ServerAnswerFailed(503),
    ]) {
      expect(isExpectedServerFailure(error), isTrue, reason: '$error');
    }
    for (final error in <Object>[
      MatrixException.fromJson({'errcode': 'M_FORBIDDEN'}),
      const ServerAnswerFailed(404),
      const ServerAnswerFailed(400, oauthError: 'invalid_client'),
      StateError('boom'),
    ]) {
      expect(isExpectedServerFailure(error), isFalse, reason: '$error');
    }
  });

  test('a failure of the server or the connection goes unreported; anything '
      'else is reported', () async {
    final reports = await reportsDuring(() async {
      for (final (label, error) in <(String, Object)>[
        ('offline', const SocketException('down')),
        ('refused', MatrixException.fromJson({'errcode': 'M_FORBIDDEN'})),
        ('broken server', const ServerAnswerFailed(502)),
        ('bug', StateError('boom')),
      ]) {
        reportUnlessServerOrNetwork(label, error, StackTrace.empty);
      }
    });

    expect(reports, ['bug']);
  });

  test('the app’s client answers the same way', () async {
    final client = ZunoClient(
      'test',
      database: FakeDatabaseApi(),
      httpClient: FakeHttpClient(
        (_) async => http.Response('<html>Bad Gateway</html>', 502),
      ),
    )..homeserver = Uri.parse('https://example.org');

    await expectLater(client.getVersions(), failedWith(502));
  });
}
