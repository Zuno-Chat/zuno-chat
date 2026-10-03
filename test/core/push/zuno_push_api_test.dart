import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/push/zuno_push_api.dart';

import '../../helpers/fake_matrix.dart';

const _base = '/_synapse/client/zuno/push/v1';

http.Response _module(Object? body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'x-zuno-push': '1', 'content-type': 'application/json'},
);

ZunoPushApi _api(
  MockClient http, {
  Future<String> Function()? bearer,
  Duration timeout = const Duration(seconds: 15),
}) => ZunoPushApi(
  homeserver: Uri.parse('https://matrix.example.org'),
  bearer: bearer ?? () async => 'Bearer syt_token',
  httpClient: http,
  timeout: timeout,
);

T _ok<T>(ZunoPushResult<T> result) => switch (result) {
  ZunoPushOk(:final value) => value,
  ZunoPushFailure(:final kind) => throw TestFailure('failed: $kind'),
};

ZunoPushFailure<T> _failure<T>(ZunoPushResult<T> result) => switch (result) {
  ZunoPushFailure() => result,
  ZunoPushOk() => throw TestFailure('expected a failure'),
};

void main() {
  group('with the Matrix bearer', () {
    late List<http.Request> requests;
    late http.Response Function(http.Request request) reply;
    late ZunoPushApi api;

    setUp(() {
      requests = [];
      reply = (_) => _module({'server_ts': 1790000000123});
      api = _api(
        MockClient((request) async {
          requests.add(request);
          return reply(request);
        }),
      );
    });

    test('registers the VoIP token and key and returns the kid the module '
        'acked', () async {
      reply = (_) => _module({'kid': 16909060, 'server_ts': 1790000000123});

      final result = await api.putVoip(
        appId: 'im.zuno.chat.ios.voip',
        pushkey: 'obLD1A==',
        kid: 16909060,
        key: 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=',
      );

      final request = requests.single;
      expect(request.method, 'PUT');
      expect(request.url.toString(), 'https://matrix.example.org$_base/voip');
      expect(request.headers['Authorization'], 'Bearer syt_token');
      expect(request.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(request.body), {
        'app_id': 'im.zuno.chat.ios.voip',
        'pushkey': 'obLD1A==',
        'kid': 16909060,
        'key': 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=',
      });
      expect(_ok(result), 16909060);
      expect((result as ZunoPushOk).serverTs, 1790000000123);
    });

    test('clears the VoIP token, and everything for this device, by '
        'DELETE', () async {
      _ok(await api.deleteVoip());
      _ok(await api.deleteDevice());

      expect(requests.map((r) => '${r.method} ${r.url.path}'), [
        'DELETE $_base/voip',
        'DELETE $_base/device',
      ]);
      expect(requests.map((r) => r.body), ['', '']);
    });

    test('reads the health of pushers, VoIP and the NSE', () async {
      reply = (_) => _module({
        'pushers': [
          {
            'app_id': 'im.zuno.chat.ios',
            'last_success_ts': 1790000000000,
            'failing_since_ts': null,
          },
        ],
        'voip': {
          'registered': true,
          'kid': 16909060,
          'last_result': 'sent',
          'last_ts': 1790000000000,
        },
        'nse': {
          'credential_expires_ts': 1792592000000,
          'last_fetch_ts': 1790000000000,
        },
        'server_ts': 1790000000123,
      });

      final health = _ok(await api.health());

      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '$_base/health');
      final pusher = health.pushers.single;
      expect(pusher.appId, 'im.zuno.chat.ios');
      expect(pusher.lastSuccessTs, 1790000000000);
      expect(pusher.failingSinceTs, isNull);
      expect(health.voip.registered, isTrue);
      expect(health.voip.kid, 16909060);
      expect(health.voip.lastResult, VoipSendResult.sent);
      expect(health.voip.lastTs, 1790000000000);
      expect(health.nse.credentialExpiresTs, 1792592000000);
      expect(health.nse.lastFetchTs, 1790000000000);
    });

    test('a health reply whose parts know nothing yet reads as nothing known, '
        'and fields the contract does not know are ignored', () async {
      reply = (_) => _module({
        'pushers': [],
        'voip': {
          'registered': null,
          'kid': null,
          'last_result': null,
          'last_ts': null,
        },
        'nse': {'credential_expires_ts': null, 'last_fetch_ts': null},
        'canary': {'ok': true},
        'server_ts': 1790000000123,
      });

      final health = _ok(await api.health());

      expect(health.pushers, isEmpty);
      expect(health.voip.registered, isFalse);
      expect(health.voip.kid, isNull);
      expect(health.voip.lastResult, isNull);
      expect(health.voip.lastTs, isNull);
      expect(health.nse.credentialExpiresTs, isNull);
      expect(health.nse.lastFetchTs, isNull);
    });

    test('a health reply naming a send result the contract does not list yet '
        'reads it as unknown', () async {
      reply = (_) => _module({
        'pushers': [
          {
            'app_id': 'im.zuno.chat.ios',
            'last_success_ts': 1790000000000,
            'failing_since_ts': null,
          },
        ],
        'voip': {
          'registered': true,
          'kid': 16909060,
          'last_result': 'later_value',
          'last_ts': 1790000000000,
        },
        'nse': {
          'credential_expires_ts': 1792592000000,
          'last_fetch_ts': 1790000000000,
        },
        'server_ts': 1790000000123,
      });

      final health = _ok(await api.health());

      expect(health.voip.lastResult, isNull);
      expect(health.voip.registered, isTrue);
      expect(health.voip.kid, 16909060);
      expect(health.voip.lastTs, 1790000000000);
      expect(health.pushers.single.appId, 'im.zuno.chat.ios');
      expect(health.nse.credentialExpiresTs, 1792592000000);
      expect(health.nse.lastFetchTs, 1790000000000);
    });

    test('asks for a test alert and returns its event id', () async {
      reply = (_) =>
          _module({'event_id': r'$zuno_test_17', 'server_ts': 1790000000123});

      final eventId = _ok(await api.sendTestAlert());

      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '$_base/test');
      expect(jsonDecode(requests.single.body), <String, Object?>{});
      expect(eventId, r'$zuno_test_17');
    });

    test('mints an NSE credential', () async {
      final credential = 'A' * 42 + '_';
      reply = (_) => _module({
        'credential': credential,
        'expires_ts': 1792592000000,
        'server_ts': 1790000000123,
      });

      final grant = _ok(await api.mintNseCredential());

      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '$_base/nse/credential');
      expect(jsonDecode(requests.single.body), <String, Object?>{});
      expect(grant.credential, credential);
      expect(grant.expiresTs, 1792592000000);
    });

    test('a reply without the module header is a route failure, whatever it '
        'says', () async {
      for (final response in [
        http.Response(
          jsonEncode({'errcode': 'M_UNRECOGNIZED', 'error': 'Unrecognized'}),
          404,
        ),
        http.Response('<html>Sign in to this Wi-Fi</html>', 200),
        http.Response(jsonEncode({'kid': 1, 'server_ts': 1}), 200),
        http.Response('Bad gateway', 502),
      ]) {
        reply = (_) => response;

        final failure = _failure(await api.deleteVoip());

        expect(failure.kind, ZunoPushFailureKind.route, reason: response.body);
        expect(failure.status, response.statusCode);
      }
    });

    test('the module header is recognized in any case', () async {
      reply = (_) => http.Response(
        jsonEncode({'server_ts': 1}),
        200,
        headers: {'X-Zuno-Push': '1'},
      );

      expect(await api.deleteVoip(), isA<ZunoPushOk<void>>());
    });

    test('each module error maps to its kind', () async {
      final cases = <(int, String, ZunoPushFailureKind)>[
        (400, 'M_INVALID_PARAM', ZunoPushFailureKind.badRequest),
        (400, 'M_NOT_JSON', ZunoPushFailureKind.badRequest),
        (401, 'M_MISSING_TOKEN', ZunoPushFailureKind.unauthorized),
        (401, 'M_UNKNOWN_TOKEN', ZunoPushFailureKind.unauthorized),
        (401, 'IM.ZUNO.BAD_CREDENTIAL', ZunoPushFailureKind.badCredential),
        (429, 'M_LIMIT_EXCEEDED', ZunoPushFailureKind.rateLimited),
        (503, 'IM.ZUNO.PUSH_DISABLED', ZunoPushFailureKind.disabled),
        (503, 'IM.ZUNO.STARTING', ZunoPushFailureKind.unexpected),
        (
          503,
          'IM.ZUNO.NOT_PUSHER_INSTANCE',
          ZunoPushFailureKind.notPusherInstance,
        ),
        (500, 'M_UNKNOWN', ZunoPushFailureKind.unexpected),
        (401, 'M_LIMIT_EXCEEDED', ZunoPushFailureKind.unexpected),
      ];
      for (final (status, errcode, kind) in cases) {
        reply = (_) =>
            _module({'errcode': errcode, 'error': 'nope'}, status: status);

        final failure = _failure(await api.sendTestAlert());

        expect(failure.kind, kind, reason: '$status $errcode');
        expect(failure.status, status);
        expect(failure.errcode, errcode);
        expect(failure.error, 'nope');
      }
    });

    test(
      'a rate limit carries the wait the module asked for, if any',
      () async {
        reply = (_) => _module({
          'errcode': 'M_LIMIT_EXCEEDED',
          'error': 'slow down',
          'retry_after_ms': 2500,
        }, status: 429);
        expect(
          _failure(await api.health()).retryAfter,
          const Duration(milliseconds: 2500),
        );

        reply = (_) => _module({'errcode': 'M_LIMIT_EXCEEDED'}, status: 429);
        expect(_failure(await api.health()).retryAfter, isNull);
      },
    );

    test('a module reply that breaks the contract is malformed', () async {
      final bodies = <Object?>[
        {'kid': 16909060},
        {'kid': '16909060', 'server_ts': 1},
        [1, 2],
        'text',
      ];
      for (final body in bodies) {
        reply = (_) => _module(body);

        final failure = _failure(
          await api.putVoip(appId: 'a', pushkey: 'p', kid: 1, key: 'k'),
        );

        expect(failure.kind, ZunoPushFailureKind.malformed, reason: '$body');
      }
      reply = (_) =>
          http.Response.bytes([0xff, 0xfe], 200, headers: {'x-zuno-push': '1'});
      expect(
        _failure(await api.deleteVoip()).kind,
        ZunoPushFailureKind.malformed,
      );
    });

    test('a health reply missing a part, or with a send result that is not a '
        'string, is malformed', () async {
      final voip = {'registered': false, 'kid': null, 'last_result': null};
      final nse = {'credential_expires_ts': null, 'last_fetch_ts': null};
      for (final body in [
        {'pushers': [], 'nse': nse, 'server_ts': 1},
        {'pushers': [], 'voip': voip, 'server_ts': 1},
        {
          'pushers': [],
          'voip': {...voip, 'last_result': 7},
          'nse': nse,
          'server_ts': 1,
        },
        {
          'pushers': [
            {'last_success_ts': 1},
          ],
          'voip': voip,
          'nse': nse,
          'server_ts': 1,
        },
      ]) {
        reply = (_) => _module(body);

        expect(
          _failure(await api.health()).kind,
          ZunoPushFailureKind.malformed,
          reason: '$body',
        );
      }
    });

    test('a credential that is not 43 base64url characters is never '
        'kept', () async {
      for (final credential in ['A' * 42, 'A' * 44, '${'A' * 42}=', '']) {
        reply = (_) => _module({
          'credential': credential,
          'expires_ts': 1,
          'server_ts': 1,
        });

        expect(
          _failure(await api.mintNseCredential()).kind,
          ZunoPushFailureKind.malformed,
          reason: credential,
        );
      }
    });
  });

  group('without a reply', () {
    test('a connection that fails is a network failure', () async {
      for (final error in [
        http.ClientException('reset'),
        const SocketException('unreachable'),
      ]) {
        final api = _api(MockClient((_) async => throw error));

        expect(
          _failure(await api.deleteDevice()).kind,
          ZunoPushFailureKind.network,
        );
      }
    });

    test('a reply that never comes is a network failure after the '
        'timeout', () {
      fakeAsync((async) {
        final api = _api(
          MockClient((_) => Completer<http.Response>().future),
          timeout: const Duration(seconds: 5),
        );
        ZunoPushResult<void>? result;
        api.deleteDevice().then((value) => result = value);

        async.elapse(const Duration(seconds: 4));
        expect(result, isNull);
        async.elapse(const Duration(seconds: 2));

        expect(_failure(result!).kind, ZunoPushFailureKind.network);
      });
    });
  });

  group('the bearer', () {
    test('without a session nothing is sent', () async {
      var sent = 0;
      final api = _api(
        MockClient((_) async {
          sent++;
          return _module({'server_ts': 1});
        }),
        bearer: () async => throw StateError('Not logged in'),
      );

      expect(_failure(await api.health()).kind, ZunoPushFailureKind.noSession);
      expect(sent, 0);
    });

    test('a session the server ended is unauthorized', () async {
      final api = _api(
        MockClient((_) async => _module({'server_ts': 1})),
        bearer: () async => throw MatrixException.fromJson({
          'errcode': 'M_UNKNOWN_TOKEN',
          'error': 'Token expired',
        }),
      );

      final failure = _failure(await api.health());

      expect(failure.kind, ZunoPushFailureKind.unauthorized);
      expect(failure.errcode, 'M_UNKNOWN_TOKEN');
    });

    test('for a signed-in client is its access token, on its '
        'homeserver', () async {
      final client = buildTestClient(userId: '@alice:example.org')
        ..homeserver = Uri.parse('https://example.org')
        ..accessToken = 'syt_alice';
      late http.Request request;
      final api = ZunoPushApi.forClient(
        client,
        httpClient: MockClient((sent) async {
          request = sent;
          return _module({'server_ts': 1});
        }),
      );

      _ok(await api.deleteVoip());

      expect(request.url.toString(), 'https://example.org$_base/voip');
      expect(request.headers['Authorization'], 'Bearer syt_alice');
    });

    test('a client with no homeserver cannot reach the module', () {
      expect(() => ZunoPushApi.forClient(buildTestClient()), throwsStateError);
    });
  });
}
