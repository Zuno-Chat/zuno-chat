import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:zuno/core/matrix/gateway_credentials.dart';

import '../../helpers/fake_matrix.dart';
import '../../helpers/in_memory_secret_store.dart';

void main() {
  final now = DateTime.utc(2026, 9, 12, 12);
  final expiresAt = now.add(const Duration(days: 30));
  const storageKey = 'calls_gateway_token:@alice:example.org:TESTDEVICE';

  http.Response ok({String token = 'gw_abc'}) => http.Response(
    jsonEncode({
      'token': token,
      'expires_at': expiresAt.millisecondsSinceEpoch,
    }),
    200,
  );

  ({
    GatewayCredentials credentials,
    List<http.Request> requests,
    InMemorySecretStore store,
  })
  build(
    http.Response Function(http.Request request) respond, {
    DateTime Function()? clock,
  }) {
    final client =
        buildTestClient(userId: '@alice:example.org', deviceId: 'TESTDEVICE')
          ..homeserver = Uri.parse('https://example.org')
          ..accessToken = 'syt_abc';
    final requests = <http.Request>[];
    final store = InMemorySecretStore();
    final credentials = GatewayCredentials(
      client: client,
      store: store,
      httpClient: MockClient((request) async {
        requests.add(request);
        return respond(request);
      }),
      now: clock ?? () => now,
    );
    return (credentials: credentials, requests: requests, store: store);
  }

  group('happy path', () {
    test(
      'enrolls once with the Matrix token and reuses the gateway token',
      () async {
        final (:credentials, :requests, :store) = build((_) => ok());

        expect(await credentials.authorization(), 'Bearer gw_abc');
        expect(await credentials.authorization(), 'Bearer gw_abc');

        expect(requests, hasLength(1));
        final enroll = requests.single;
        expect(enroll.method, 'POST');
        expect(enroll.url.toString(), 'https://example.org/calls/enroll');
        expect(enroll.headers['Authorization'], 'Bearer syt_abc');
        expect(jsonDecode(enroll.body), {'device_id': 'TESTDEVICE'});
        expect(store.values.keys.single, storageKey);
      },
    );

    test('concurrent callers share one enrollment', () async {
      final (:credentials, :requests, :store) = build((_) => ok());
      final tokens = await Future.wait([
        credentials.token(),
        credentials.token(),
      ]);
      expect(tokens, ['gw_abc', 'gw_abc']);
      expect(requests, hasLength(1));
      expect(store.writes, 1);
    });

    test(
      'a plain call and a concurrent refresh share one enrollment',
      () async {
        var n = 0;
        final (:credentials, :requests, :store) = build(
          (_) => ok(token: 'gw_${++n}'),
        );
        final tokens = await Future.wait([
          credentials.token(),
          credentials.token(refresh: true),
        ]);
        expect(tokens, ['gw_1', 'gw_1']);
        expect(requests, hasLength(1));
        expect(store.writes, 1);
      },
    );

    test('two concurrent refreshes share one enrollment', () async {
      var n = 0;
      final (:credentials, :requests, :store) = build(
        (_) => ok(token: 'gw_${++n}'),
      );
      final tokens = await Future.wait([
        credentials.token(refresh: true),
        credentials.token(refresh: true),
      ]);
      expect(tokens, ['gw_1', 'gw_1']);
      expect(requests, hasLength(1));
      expect(store.writes, 1);
    });

    test('refresh re-enrolls even with a valid stored token', () async {
      var n = 0;
      final (:credentials, :requests, store: _) = build(
        (_) => ok(token: 'gw_${++n}'),
      );
      expect(await credentials.token(), 'gw_1');
      expect(await credentials.token(refresh: true), 'gw_2');
      expect(await credentials.token(), 'gw_2');
      expect(requests, hasLength(2));
    });

    test('revoke deletes the stored token and tells the gateway', () async {
      final (:credentials, :requests, :store) = build((_) => ok());
      await credentials.token();
      await credentials.revoke();

      expect(store.values, isEmpty);
      final revoke = requests.last;
      expect(revoke.method, 'DELETE');
      expect(revoke.url.path, '/calls/enroll');
      expect(revoke.headers['Authorization'], 'Bearer gw_abc');
    });

    test('a stored token is read from storage once and then cached', () async {
      final (:credentials, :requests, :store) = build((_) => ok());
      await credentials.token();
      final readsAfterEnroll = store.reads;
      await credentials.token();
      await credentials.token();
      expect(store.reads, readsAfterEnroll);
      expect(requests, hasLength(1));
    });

    test(
      'a token cached fresh is later found stale by the same instance',
      () async {
        var n = 0;
        var current = now;
        final (:credentials, :requests, :store) = build(
          (_) => http.Response(
            jsonEncode({
              'token': 'gw_${++n}',
              'expires_at': current
                  .add(const Duration(days: 30))
                  .millisecondsSinceEpoch,
            }),
            200,
          ),
          clock: () => current,
        );

        expect(await credentials.token(), 'gw_1');
        expect(requests, hasLength(1));
        final readsAfterFirst = store.reads;

        current = expiresAt.add(const Duration(seconds: 1));
        expect(await credentials.token(), 'gw_2');
        expect(requests, hasLength(2));
        expect(store.reads, readsAfterFirst);
      },
    );

    test(
      'a token expiring inside the margin is replaced, outside it is kept',
      () async {
        var n = 0;
        final (:credentials, :requests, :store) = build(
          (_) => ok(token: 'gw_${++n}'),
        );
        store.values[storageKey] = jsonEncode({
          'token': 'gw_soon',
          'expires_at': now
              .add(const Duration(seconds: 30))
              .millisecondsSinceEpoch,
        });
        expect(await credentials.token(), 'gw_1');
        expect(requests, hasLength(1));

        final (credentials: fresh, requests: freshRequests, store: freshStore) =
            build((_) => ok(token: 'gw_unused'));
        freshStore.values[storageKey] = jsonEncode({
          'token': 'gw_later',
          'expires_at': now
              .add(const Duration(seconds: 90))
              .millisecondsSinceEpoch,
        });
        expect(await fresh.token(), 'gw_later');
        expect(freshRequests, isEmpty);
      },
    );

    test(
      'a plain read overlapping a refresh returns the refreshed token',
      () async {
        var n = 0;
        final (:credentials, :requests, :store) = build(
          (_) => ok(token: 'gw_${++n}'),
        );
        store.values[storageKey] = jsonEncode({
          'token': 'gw_stored',
          'expires_at': expiresAt.millisecondsSinceEpoch,
        });
        final gate = Completer<void>();
        store.beforeRead = () => gate.future;
        final plain = credentials.token();
        final refreshed = credentials.token(refresh: true);
        gate.complete();
        expect(await Future.wait([plain, refreshed]), ['gw_1', 'gw_1']);
        expect(requests, hasLength(1));
      },
    );

    test('a plain read resuming after the refresh finished does not cache the stale token', () async {
      var n = 0;
      final (:credentials, :requests, :store) = build(
        (_) => ok(token: 'gw_${++n}'),
      );
      store.values[storageKey] = jsonEncode({
        'token': 'gw_stored',
        'expires_at': expiresAt.millisecondsSinceEpoch,
      });
      final gate = Completer<void>();
      store.beforeRead = () => gate.future;

      final plain = credentials.token();
      expect(await credentials.token(refresh: true), 'gw_1');
      gate.complete();

      expect(await plain, 'gw_1');
      store.beforeRead = null;
      expect(await credentials.token(), 'gw_1');
      expect(requests, hasLength(1));
    });
  });

  group('sad paths', () {
    test('an expired stored token is replaced', () async {
      final (:credentials, :requests, :store) = build((_) => ok());
      store.values[storageKey] = jsonEncode({
        'token': 'gw_stale',
        'expires_at': now
            .subtract(const Duration(seconds: 1))
            .millisecondsSinceEpoch,
      });
      expect(await credentials.token(), 'gw_abc');
      expect(requests, hasLength(1));
    });

    test('a 4xx enrollment fails without retrying', () async {
      final (:credentials, :requests, store: _) = build(
        (_) => http.Response('nope', 403),
      );
      await expectLater(
        credentials.token(),
        throwsA(isA<GatewayEnrollmentException>()),
      );
      expect(requests, hasLength(1));
    });

    test('a 5xx enrollment is retried and then succeeds', () {
      fakeAsync((async) {
        var n = 0;
        final (:credentials, :requests, store: _) = build(
          (_) => ++n < 3 ? http.Response('down', 503) : ok(),
        );
        String? token;
        credentials.token().then((value) => token = value);
        async.elapse(const Duration(seconds: 5));
        expect(token, 'gw_abc');
        expect(requests, hasLength(3));
      });
    });

    test('a socket error is retried', () {
      fakeAsync((async) {
        var n = 0;
        final (:credentials, requests: _, store: _) = build((_) {
          if (++n == 1) throw const SocketException('unreachable');
          return ok();
        });
        String? token;
        credentials.token().then((value) => token = value);
        async.elapse(const Duration(seconds: 5));
        expect(token, 'gw_abc');
      });
    });

    test('a response without a token is rejected', () async {
      final (:credentials, requests: _, store: _) = build(
        (_) => http.Response(jsonEncode({'expires_at': 1}), 200),
      );
      await expectLater(
        credentials.token(),
        throwsA(isA<GatewayEnrollmentException>()),
      );
    });

    test('an already-expired enroll response is rejected', () async {
      final (:credentials, requests: _, store: _) = build(
        (_) => http.Response(
          jsonEncode({
            'token': 'gw_abc',
            'expires_at': now
                .subtract(const Duration(seconds: 1))
                .millisecondsSinceEpoch,
          }),
          200,
        ),
      );
      await expectLater(
        credentials.token(),
        throwsA(isA<GatewayEnrollmentException>()),
      );
    });

    test('a malformed enroll response does not leak the token', () async {
      final (:credentials, requests: _, store: _) = build(
        (_) => http.Response(
          jsonEncode({'token': 'gw_super_secret', 'expires_at': 'soon'}),
          200,
        ),
      );
      Object? error;
      try {
        await credentials.token();
      } catch (e) {
        error = e;
      }
      expect(error, isA<GatewayEnrollmentException>());
      expect(error.toString(), isNot(contains('gw_super_secret')));
    });

    test('revoke without a stored token only clears storage', () async {
      final (:credentials, :requests, store: _) = build((_) => ok());
      await credentials.revoke();
      expect(requests, isEmpty);
    });

    test('revoke surfaces a gateway delete failure to the caller', () async {
      final (:credentials, requests: _, store: _) = build((request) {
        if (request.method == 'DELETE') {
          throw const SocketException('unreachable');
        }
        return ok();
      });
      await credentials.token();
      await expectLater(credentials.revoke(), throwsA(isA<SocketException>()));
    });

    test('a client without a device id refuses', () async {
      final client = buildTestClient(userId: '@alice:example.org')
        ..homeserver = Uri.parse('https://example.org')
        ..accessToken = 'syt_abc';
      final credentials = GatewayCredentials(
        client: client,
        store: InMemorySecretStore(),
        httpClient: MockClient((_) async => ok()),
      );
      await expectLater(credentials.token(), throwsStateError);
    });

    test('a storage read failure enrolls instead of failing', () async {
      final (:credentials, :requests, :store) = build((_) => ok());
      store.failReads = true;
      expect(await credentials.token(), 'gw_abc');
      expect(requests, hasLength(1));
    });

    test('a storage write failure still returns the minted token', () async {
      final (:credentials, :requests, :store) = build((_) => ok());
      store.failWrites = true;
      expect(await credentials.token(), 'gw_abc');
      expect(await credentials.token(), 'gw_abc');
      expect(requests, hasLength(1));
    });

    test('revoke tolerates a storage read failure', () async {
      final (:credentials, :requests, :store) = build((_) => ok());
      await credentials.token();
      store.failReads = true;
      await expectLater(credentials.revoke(), completes);
      expect(requests.last.method, 'DELETE');
    });

    test('revoke tolerates a storage delete failure', () async {
      final (:credentials, :requests, :store) = build((_) => ok());
      await credentials.token();
      store.failDeletes = true;
      await expectLater(credentials.revoke(), completes);
      expect(requests.last.method, 'DELETE');
    });

    test('close releases an internally created client only', () async {
      final client =
          buildTestClient(userId: '@alice:example.org', deviceId: 'TESTDEVICE')
            ..homeserver = Uri.parse('https://example.org')
            ..accessToken = 'syt_abc';
      final mock = MockClient((_) async => ok());
      final owned = GatewayCredentials(
        client: client,
        store: InMemorySecretStore(),
      );
      final borrowed = GatewayCredentials(
        client: client,
        store: InMemorySecretStore(),
        httpClient: mock,
      );
      owned.close();
      borrowed.close();
      expect(await borrowed.token(), 'gw_abc');
    });
  });
}
