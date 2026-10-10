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

  const finalStatuses = {
    401: 'a 401 is final and surfaces as CloudflareTurnException',
    403: 'does not retry a 4xx response',
    502: 'a 5xx is final: the module already retried Cloudflare',
  };
  for (final MapEntry(key: status, value: name) in finalStatuses.entries) {
    test(name, () async {
      var calls = 0;
      final mock = MockClient((request) async {
        calls++;
        return http.Response('{"errcode":"M_UNKNOWN"}', status);
      });

      await expectLater(
        _fetch(mock),
        throwsA(
          isA<CloudflareTurnException>()
              .having((e) => e.statusCode, 'statusCode', status)
              .having(
                (e) => e.message,
                'message',
                'HTTP $status from TURN credentials: M_UNKNOWN',
              ),
        ),
      );
      expect(calls, 1);
    });
  }

  test(
    'throws CloudflareTurnException when the response has no iceServers field',
    () {
      final mock = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'iceServers': {'username': 'u1', 'credential': 'c1'},
          }),
          201,
        ),
      );
      expect(
        _fetch(mock),
        throwsA(
          isA<CloudflareTurnException>().having(
            (e) => e.message,
            'message',
            'TURN credentials returned no ICE servers',
          ),
        ),
      );
    },
  );

  for (final dropped in <Exception>[
    const SocketException('connection refused'),
    http.ClientException('connection closed before full header was received'),
  ]) {
    test('retries a ${dropped.runtimeType} and returns the servers once it '
        'succeeds', () {
      fakeAsync((async) {
        var calls = 0;
        final mock = MockClient((request) async {
          calls++;
          if (calls == 1) throw dropped;
          return _servers();
        });
        List<Map<String, Object?>>? servers;
        _fetch(mock).then((s) => servers = s);

        async.elapse(const Duration(seconds: 5));

        expect(calls, 2);
        expect(servers, isEmpty);
      });
    });
  }

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
