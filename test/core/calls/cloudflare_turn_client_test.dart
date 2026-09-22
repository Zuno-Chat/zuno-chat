import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:zuno/core/calls/cloudflare/cloudflare_turn_client.dart';

final _credentialsUri = Uri.parse(
  'https://example.org/_synapse/client/zuno/calls/cloudflare/turn/credentials',
);

Future<String> _authorization() async => 'Bearer syt_token';

Future<List<Map<String, Object?>>> _fetch(http.Client mock) =>
    fetchCloudflareIceServers(
      credentialsUri: _credentialsUri,
      authorization: _authorization,
      httpClient: mock,
    );

http.Response _servers() =>
    http.Response(jsonEncode({'iceServers': <Object?>[]}), 201);

void main() {
  test('posts the Matrix bearer with no body and returns iceServers', () async {
    final mock = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url, _credentialsUri);
      expect(request.headers['Authorization'], 'Bearer syt_token');
      expect(request.body, isEmpty);
      expect(request.headers.containsKey('content-type'), isFalse);
      return http.Response(
        jsonEncode({
          'iceServers': [
            {
              'urls': ['stun:stun.cloudflare.com:3478'],
            },
            {
              'urls': ['turn:turn.cloudflare.com:3478?transport=udp'],
              'username': 'u1',
              'credential': 'c1',
            },
          ],
        }),
        201,
      );
    });

    final servers = await _fetch(mock);

    expect(servers, hasLength(2));
    expect(servers[1]['username'], 'u1');
    expect(servers[1]['credential'], 'c1');
  });

  test('a 401 is final and surfaces as CloudflareTurnException', () async {
    var calls = 0;
    final mock = MockClient((request) async {
      calls++;
      return http.Response('{"errcode":"M_UNKNOWN_TOKEN"}', 401);
    });
    await expectLater(
      _fetch(mock),
      throwsA(
        isA<CloudflareTurnException>().having(
          (e) => e.statusCode,
          'statusCode',
          401,
        ),
      ),
    );
    expect(calls, 1);
  });

  test(
    'throws CloudflareTurnException when the response has no iceServers field',
    () {
      final mock = MockClient(
        (request) async => http.Response(jsonEncode({}), 201),
      );
      expect(_fetch(mock), throwsA(isA<CloudflareTurnException>()));
    },
  );

  test(
    'retries a SocketException and returns the servers once it succeeds',
    () {
      fakeAsync((async) {
        var calls = 0;
        final mock = MockClient((request) async {
          calls++;
          if (calls == 1) throw const SocketException('connection refused');
          return _servers();
        });
        List<Map<String, Object?>>? servers;
        _fetch(mock).then((s) => servers = s);

        async.elapse(const Duration(seconds: 5));

        expect(calls, 2);
        expect(servers, isEmpty);
      });
    },
  );

  test('a 5xx is final: the module already retried Cloudflare', () {
    fakeAsync((async) {
      var calls = 0;
      final mock = MockClient((request) async {
        calls++;
        return http.Response('{"errcode":"M_UNKNOWN"}', 502);
      });
      Object? error;
      () async {
        try {
          await _fetch(mock);
        } catch (e) {
          error = e;
        }
      }();

      async.elapse(const Duration(seconds: 5));

      expect(calls, 1);
      expect(error, isA<CloudflareTurnException>());
    });
  });

  test('a 429 waits retry_after_ms and then retries', () {
    fakeAsync((async) {
      var calls = 0;
      final mock = MockClient((request) async {
        calls++;
        if (calls == 1) {
          return http.Response(
            jsonEncode({'errcode': 'M_LIMIT_EXCEEDED', 'retry_after_ms': 400}),
            429,
          );
        }
        return _servers();
      });
      List<Map<String, Object?>>? servers;
      _fetch(mock).then((s) => servers = s);

      async.elapse(const Duration(milliseconds: 399));
      expect(calls, 1);
      async.elapse(const Duration(milliseconds: 1));
      expect(calls, 2);
      expect(servers, isEmpty);
    });
  });

  test('does not retry a 4xx response', () {
    fakeAsync((async) {
      var calls = 0;
      final mock = MockClient((request) async {
        calls++;
        return http.Response('forbidden', 403);
      });
      Object? error;
      () async {
        try {
          await _fetch(mock);
        } catch (e) {
          error = e;
        }
      }();

      async.elapse(const Duration(seconds: 5));

      expect(calls, 1);
      expect(error, isA<CloudflareTurnException>());
    });
  });

  test('an authorization failure is not retried', () async {
    var calls = 0;
    final mock = MockClient((request) async => _servers());
    await expectLater(
      fetchCloudflareIceServers(
        credentialsUri: _credentialsUri,
        authorization: () async {
          calls++;
          throw StateError('Not logged in');
        },
        httpClient: mock,
      ),
      throwsStateError,
    );
    expect(calls, 1);
  });
}
