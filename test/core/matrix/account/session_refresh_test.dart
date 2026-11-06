import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/matrix/account/session_refresh.dart';
import 'package:zuno/core/matrix/http/refresh_deadline_http_client.dart';

import '../../../helpers/fake_http.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/oauth_server.dart';

class _ClientRowDatabase extends FakeDatabaseApi with MediaCapableDatabase {
  _ClientRowDatabase({String? refreshToken, String? oidcClientId}) {
    if (refreshToken != null) row['refresh_token'] = refreshToken;
    if (oidcClientId != null) row['oidc_client_id'] = oidcClientId;
  }

  final Map<String, dynamic> row = {'token': 'a0'};

  @override
  Future<Map<String, dynamic>?> getClient(String name) async => Map.of(row);

  @override
  Future<void> storeClient({
    required String homeserverUrl,
    required String token,
    DateTime? tokenExpiresAt,
    String? refreshToken,
    required String userId,
    String? deviceId,
    String? deviceName,
    String? prevBatch,
    String? olmAccount,
    String? oidcClientId,
  }) async {
    row['token'] = token;
    row['refresh_token'] = refreshToken;
  }

  @override
  Future<void> clear() async => row.clear();
}

class _StaleMetadataDatabase extends _ClientRowDatabase {
  _StaleMetadataDatabase()
    : super(refreshToken: 'r0', oidcClientId: 'client-1');

  @override
  Future<({Map<String, Object?> content, DateTime savedAt})?>
  getCustomCacheObject(String cacheKey) async => (
    content: oauthMetadata,
    savedAt: clock.now().subtract(const Duration(days: 10)),
  );
}

class _StalledMetadataServer extends http.BaseClient {
  final tokenRequests = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path == '/_matrix/client/v1/auth_metadata') {
      final never = Completer<http.StreamedResponse>();
      if (request case http.Abortable(:final abortTrigger?)) {
        unawaited(
          abortTrigger.whenComplete(
            () =>
                never.completeError(http.RequestAbortedException(request.url)),
          ),
        );
      }
      return never.future;
    }
    tokenRequests.add(await request.finalize().bytesToString());
    return http.StreamedResponse(
      fakeTimeBody(
        utf8.encode(
          jsonEncode({
            'access_token': 'a1',
            'token_type': 'Bearer',
            'refresh_token': 'r1',
            'expires_in': 300,
          }),
        ),
      ),
      200,
    );
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
        fakeTimeBody(
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
  DateTime? get accessTokenExpiresAt => clock.now();
}

http.Response _json(int status, Map<String, Object?> body) =>
    http.Response(jsonEncode(body), status);

String _sentRefreshToken(http.Request request) =>
    (jsonDecode(request.body) as Map)['refresh_token'] as String;

Client _client(_ClientRowDatabase database, FakeHttpClient server) =>
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
      final server = FakeHttpClient((request) async {
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

  test(
    'a refused refresh with nothing newer stored ends the session',
    () async {
      final database = _ClientRowDatabase(refreshToken: 'r0');
      var requests = 0;
      final server = FakeHttpClient((request) async {
        requests++;
        return _json(401, {'errcode': 'M_UNKNOWN_TOKEN'});
      });
      final client = _client(database, server);

      await expectLater(
        refreshSession(client, settle: Duration.zero),
        throwsA(
          isA<SessionEnded>().having((e) => e.code, 'code', 'M_UNKNOWN_TOKEN'),
        ),
      );
      expect(requests, 1);
      expect(client.isLogged(), isFalse);
    },
  );

  test(
    'a refusal of the retry with the newer token ends the session',
    () async {
      final database = _ClientRowDatabase(refreshToken: 'r0');
      final sent = <String>[];
      final server = FakeHttpClient((request) async {
        final token = _sentRefreshToken(request);
        sent.add(token);
        if (token == 'r0') database.row['refresh_token'] = 'r1';
        return _json(403, {'errcode': 'M_FORBIDDEN'});
      });
      final client = _client(database, server);

      await expectLater(
        refreshSession(client, settle: Duration.zero),
        throwsA(isA<SessionEnded>()),
      );
      expect(sent, ['r0', 'r1']);
      expect(client.isLogged(), isFalse);
    },
  );

  test(
    'a session ended by a failed refresh never blocks the next sign-in',
    () async {
      final database = _ClientRowDatabase();
      final sent = <String>[];
      final server = FakeHttpClient((request) async {
        sent.add(_sentRefreshToken(request));
        return _json(200, {
          'access_token': 'a2',
          'refresh_token': 'r2',
          'expires_in_ms': 300000,
        });
      });
      final client = _ExpiringClient(database, server);

      await client.ensureNotSoftLoggedOut();
      expect(client.isLogged(), isFalse);
      expect(client.onLoginStateChanged.value, LoginState.loggedOut);

      client
        ..setUserId('@alice:example.org')
        ..homeserver = Uri.parse('https://example.org')
        ..accessToken = 'a1';
      database.row['refresh_token'] = 'r1';
      await client.ensureNotSoftLoggedOut();

      expect(sent, ['r1']);
      expect(client.accessToken, 'a2');
      expect(database.row['refresh_token'], 'r2');
    },
  );

  test(
    'a refresh failure is wrapped with its errcode and nothing else',
    () async {
      final database = _ClientRowDatabase(refreshToken: 'r0');
      final server = FakeHttpClient(
        (request) async =>
            _json(500, {'errcode': 'M_UNKNOWN', 'error': 'secret detail'}),
      );
      final client = _client(database, server);

      await expectLater(
        refreshSession(client, settle: Duration.zero),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            'Exception: Token refresh failed: M_UNKNOWN',
          ),
        ),
      );
    },
  );

  for (final (label, answer) in <(String, http.Response Function())>[
    ('rate limit', () => _json(429, {'errcode': 'M_LIMIT_EXCEEDED'})),
    ('server error', () => _json(500, {'errcode': 'M_UNKNOWN'})),
    ('network failure', () => throw http.ClientException('offline')),
  ]) {
    test('a $label during refresh is not treated as a dead session', () async {
      final database = _ClientRowDatabase(refreshToken: 'r0');
      var requests = 0;
      final server = FakeHttpClient((request) async {
        requests++;
        return answer();
      });
      final client = _client(database, server);

      await expectLater(
        refreshSession(client, settle: Duration.zero),
        throwsA(isNot(isA<MatrixException>())),
      );
      expect(requests, 1);
      expect(client.isLogged(), isTrue);
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

    test('an OAuth refresh whose stale metadata request is never answered '
        'is given up at the deadline and carries on with the cached '
        'metadata', () {
      fakeAsync((async) {
        final database = _StaleMetadataDatabase();
        final oauthServer = _StalledMetadataServer();
        final oauthClient = _ExpiringClient(
          database,
          RefreshDeadlineHttpClient(oauthServer),
        );
        var carriedOn = false;
        unawaited(
          oauthClient.ensureNotSoftLoggedOut().then((_) => carriedOn = true),
        );

        async.elapse(refreshBound - const Duration(milliseconds: 1));
        expect(carriedOn, isFalse);

        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        expect(carriedOn, isTrue);
        expect(oauthServer.tokenRequests, hasLength(1));
        expect(oauthClient.accessToken, 'a1');
        expect(database.row['refresh_token'], 'r1');
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

  group('an OAuth session', () {
    late _ClientRowDatabase database;
    late List<http.Request> tokenRequests;
    late FakeHttpClient server;
    late Client client;
    late http.Response Function(Map<String, String> form) tokenAnswer;

    http.Response granted(String access, String refresh) => _json(200, {
      'access_token': access,
      'token_type': 'Bearer',
      'refresh_token': refresh,
      'expires_in': 300,
    });

    setUp(() {
      database = _ClientRowDatabase(
        refreshToken: 'r0',
        oidcClientId: 'client-1',
      );
      tokenRequests = [];
      tokenAnswer = (_) => granted('a1', 'r1');
      server = FakeHttpClient((request) async {
        if (request.url.path == '/_matrix/client/v1/auth_metadata') {
          return _json(200, oauthMetadata);
        }
        if (request.url.path == '/token') {
          tokenRequests.add(request);
          return tokenAnswer(Uri.splitQueryString(request.body));
        }
        return _json(404, {'errcode': 'M_NOT_FOUND'});
      });
      client = _client(database, server);
    });

    test(
      'an OAuth refresh posts the refresh grant with the client id',
      () async {
        await refreshSession(client, settle: Duration.zero);

        final form = Uri.splitQueryString(tokenRequests.single.body);
        expect(form, {
          'grant_type': 'refresh_token',
          'refresh_token': 'r0',
          'client_id': 'client-1',
        });
        expect(client.accessToken, 'a1');
        expect(database.row['refresh_token'], 'r1');
      },
    );

    test('invalid_grant with a rotated stored token retries once', () async {
      tokenAnswer = (form) {
        if (form['refresh_token'] == 'r0') {
          database.row['refresh_token'] = 'r1';
          return _json(400, {'error': 'invalid_grant'});
        }
        return granted('a2', 'r2');
      };

      await refreshSession(client, settle: Duration.zero);

      expect(
        tokenRequests.map((r) => Uri.splitQueryString(r.body)['refresh_token']),
        ['r0', 'r1'],
      );
      expect(client.accessToken, 'a2');
      expect(database.row['refresh_token'], 'r2');
    });

    test('invalid_grant with an unchanged token ends the session', () async {
      tokenAnswer = (_) => _json(400, {'error': 'invalid_grant'});

      await expectLater(
        refreshSession(client, settle: Duration.zero),
        throwsA(
          isA<SessionEnded>().having((e) => e.code, 'code', 'invalid_grant'),
        ),
      );
      expect(tokenRequests, hasLength(1));
      expect(client.isLogged(), isFalse);
    });

    test('server_error is wrapped, not rethrown', () async {
      tokenAnswer = (_) => _json(400, {'error': 'server_error'});

      await expectLater(
        refreshSession(client, settle: Duration.zero),
        throwsA(
          isA<Exception>()
              .having(
                (e) => e,
                'not an OidcException',
                isNot(isA<OidcException>()),
              )
              .having(
                (e) => e.toString(),
                'message',
                'Exception: Token refresh failed: server_error',
              ),
        ),
      );
      expect(tokenRequests, hasLength(1));
    });
  });

  test(
    'a client already signed out is ended without asking the server',
    () async {
      final database = _ClientRowDatabase(refreshToken: 'r0');
      var requests = 0;
      final server = FakeHttpClient((request) async {
        requests++;
        return _json(200, {});
      });
      final client = _client(database, server)..accessToken = null;

      await expectLater(
        refreshSession(client, settle: Duration.zero),
        throwsA(isA<SessionEnded>()),
      );
      expect(requests, 0);
    },
  );

  test('a session with no refresh token is ended, not retried', () async {
    final database = _ClientRowDatabase();
    var requests = 0;
    final server = FakeHttpClient((request) async {
      requests++;
      return _json(200, {});
    });
    final client = _client(database, server);

    await expectLater(
      refreshSession(client, settle: Duration.zero),
      throwsA(isA<SessionEnded>()),
    );
    expect(requests, 0);
    expect(client.isLogged(), isFalse);
  });
}
