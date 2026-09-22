import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/session_refresh.dart';

import '../../helpers/fake_matrix.dart';

class _ClientRowDatabase extends FakeDatabaseApi {
  _ClientRowDatabase({String? refreshToken}) {
    if (refreshToken != null) row['refresh_token'] = refreshToken;
  }

  final Map<String, dynamic> row = {'token': 'a0'};

  @override
  Future<Map<String, dynamic>?> getClient(String name) async => Map.of(row);

  @override
  Future<void> updateClient(
    String homeserverUrl,
    String token,
    DateTime? tokenExpiresAt,
    String? refreshToken,
    String userId,
    String? deviceId,
    String? deviceName,
    String? prevBatch,
    String? olmAccount,
    String? oidcClientId,
  ) async {
    row['token'] = token;
    row['refresh_token'] = refreshToken;
  }
}

http.Response _json(int status, Map<String, Object?> body) =>
    http.Response(jsonEncode(body), status);

String _sentRefreshToken(http.Request request) =>
    (jsonDecode(request.body) as Map)['refresh_token'] as String;

Client _client(_ClientRowDatabase database, MockClient server) =>
    buildTestClient(
        userId: '@alice:example.org',
        deviceId: 'DEVICE',
        httpClient: server,
        database: database,
      )
      ..homeserver = Uri.parse('https://example.org')
      ..accessToken = 'a0';

void main() {
  test(
    'a refused refresh retries with the token another process stored',
    () async {
      final database = _ClientRowDatabase(refreshToken: 'r0');
      final sent = <String>[];
      final server = MockClient((request) async {
        final token = _sentRefreshToken(request);
        sent.add(token);
        if (token == 'r0') {
          database.row['refresh_token'] = 'r1';
          return _json(403, {'errcode': 'M_FORBIDDEN'});
        }
        return _json(200, {
          'access_token': 'a2',
          'refresh_token': 'r2',
          'expires_in_ms': 86400000,
        });
      });
      final client = _client(database, server);

      await refreshSession(client, settle: Duration.zero);

      expect(sent, ['r0', 'r1']);
      expect(client.accessToken, 'a2');
      expect(database.row['refresh_token'], 'r2');
    },
  );

  test('a refused refresh with nothing newer stored gives up', () async {
    final database = _ClientRowDatabase(refreshToken: 'r0');
    var requests = 0;
    final server = MockClient((request) async {
      requests++;
      return _json(401, {'errcode': 'M_UNKNOWN_TOKEN'});
    });
    final client = _client(database, server);

    await expectLater(
      refreshSession(client, settle: Duration.zero),
      throwsA(isA<MatrixException>()),
    );
    expect(requests, 1);
  });

  for (final (label, status, errcode) in [
    ('rate limit', 429, 'M_LIMIT_EXCEEDED'),
    ('server error', 500, 'M_UNKNOWN'),
  ]) {
    test('a $label during refresh is not treated as a dead session', () async {
      final database = _ClientRowDatabase(refreshToken: 'r0');
      var requests = 0;
      final server = MockClient((request) async {
        requests++;
        return _json(status, {'errcode': errcode});
      });
      final client = _client(database, server);

      await expectLater(
        refreshSession(client, settle: Duration.zero),
        throwsA(isNot(isA<MatrixException>())),
      );
      expect(requests, 1);
    });
  }

  test('a network failure is not treated as a dead session', () async {
    final database = _ClientRowDatabase(refreshToken: 'r0');
    var requests = 0;
    final server = MockClient((request) async {
      requests++;
      throw http.ClientException('offline');
    });
    final client = _client(database, server);

    await expectLater(
      refreshSession(client, settle: Duration.zero),
      throwsA(isNot(isA<MatrixException>())),
    );
    expect(requests, 1);
  });

  test('a session with no refresh token is given up, not retried', () async {
    final database = _ClientRowDatabase();
    var requests = 0;
    final server = MockClient((request) async {
      requests++;
      return _json(200, {});
    });
    final client = _client(database, server);

    await expectLater(
      refreshSession(client, settle: Duration.zero),
      throwsA(isA<MatrixException>()),
    );
    expect(requests, 0);
  });
}
