import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/refresh_deadline_http_client.dart';
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

class _HeldRefreshes extends http.BaseClient {
  final sent = <String>[];
  final _answers = <Completer<http.StreamedResponse>>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().bytesToString();
    sent.add((jsonDecode(body) as Map)['refresh_token'] as String);
    final answer = Completer<http.StreamedResponse>();
    _answers.add(answer);
    if (request case http.Abortable(:final abortTrigger?)) {
      unawaited(
        abortTrigger.whenComplete(() {
          if (!answer.isCompleted) {
            answer.completeError(http.RequestAbortedException(request.url));
          }
        }),
      );
    }
    return answer.future;
  }

  void answer(int index, {required String access, required String refresh}) {
    final answer = _answers[index];
    if (answer.isCompleted) return;
    answer.complete(
      http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode({
              'access_token': access,
              'refresh_token': refresh,
              'expires_in_ms': 86400000,
            }),
          ),
        ),
        200,
      ),
    );
  }
}

class _ExpiringClient extends Client {
  _ExpiringClient(_ClientRowDatabase database, http.Client server)
    : super(
        'test',
        database: database,
        httpClient: server,
        onSoftLogout: refreshSession,
      ) {
    setUserId('@alice:example.org');
    homeserver = Uri.parse('https://example.org');
    accessToken = 'a0';
  }

  @override
  String? get deviceID => 'DEVICE';

  @override
  DateTime? get accessTokenExpiresAt => DateTime.now();
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

  for (final (label, answer) in <(String, http.Response Function())>[
    ('rate limit', () => _json(429, {'errcode': 'M_LIMIT_EXCEEDED'})),
    ('server error', () => _json(500, {'errcode': 'M_UNKNOWN'})),
    ('network failure', () => throw http.ClientException('offline')),
  ]) {
    test('a $label during refresh is not treated as a dead session', () async {
      final database = _ClientRowDatabase(refreshToken: 'r0');
      var requests = 0;
      final server = MockClient((request) async {
        requests++;
        return answer();
      });
      final client = _client(database, server);

      await expectLater(
        refreshSession(client, settle: Duration.zero),
        throwsA(isNot(isA<MatrixException>())),
      );
      expect(requests, 1);
    });
  }

  group('a refresh the server does not answer', () {
    late _ClientRowDatabase database;
    late _HeldRefreshes server;
    late Client client;

    setUp(() {
      database = _ClientRowDatabase(refreshToken: 'r0');
      server = _HeldRefreshes();
      client = _ExpiringClient(database, RefreshDeadlineHttpClient(server));
    });

    test('is given up at its deadline, and what waits on it carries on with '
        'the session kept', () {
      fakeAsync((async) {
        var carriedOn = false;
        unawaited(
          client.ensureNotSoftLoggedOut().then((_) => carriedOn = true),
        );

        async.elapse(refreshBound - const Duration(milliseconds: 1));
        expect(carriedOn, isFalse);

        async.elapse(const Duration(milliseconds: 1));
        expect(carriedOn, isTrue);
        expect(client.accessToken, 'a0');
        expect(database.row['refresh_token'], 'r0');
      });
    });

    test('never lands later over the refresh that followed it', () async {
      final quick = _ExpiringClient(
        database,
        RefreshDeadlineHttpClient(
          server,
          deadline: const Duration(milliseconds: 20),
        ),
      );

      await quick.ensureNotSoftLoggedOut();
      final second = quick.ensureNotSoftLoggedOut();
      await pumpEventQueue();
      server.answer(1, access: 'a2', refresh: 'r2');
      await second;
      server.answer(0, access: 'a1', refresh: 'r1');
      await pumpEventQueue();

      expect(server.sent, ['r0', 'r0']);
      expect(quick.accessToken, 'a2');
      expect(database.row['refresh_token'], 'r2');
    });
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
