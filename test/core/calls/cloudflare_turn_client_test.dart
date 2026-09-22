import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:zuno/core/calls/cloudflare/calls_gateway_credentials.dart';
import 'package:zuno/core/calls/cloudflare/cloudflare_turn_client.dart';

Future<String> _authorization({bool refresh = false}) async =>
    'Bearer syt_token';

void main() {
  test('returns the iceServers list from a 201 response', () async {
    final mock = MockClient((request) async {
      expect(request.url.toString(), 'https://example.org/turn/credentials');
      expect(request.headers['Authorization'], 'Bearer syt_token');
      expect(jsonDecode(request.body), {'ttl': 86400});
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

    final servers = await fetchCloudflareIceServers(
      credentialsUri: Uri.parse('https://example.org/turn/credentials'),
      authorizationProvider: _authorization,
      httpClient: mock,
      ttl: const Duration(hours: 24),
    );

    expect(servers, hasLength(2));
    expect(servers[1]['username'], 'u1');
    expect(servers[1]['credential'], 'c1');
  });

  test('throws CloudflareTurnException on a non-2xx response', () {
    final mock = MockClient(
      (request) async => http.Response('unauthorized', 401),
    );
    expect(
      fetchCloudflareIceServers(
        credentialsUri: Uri.parse('https://example.org/turn/credentials'),
        authorizationProvider: _authorization,
        httpClient: mock,
      ),
      throwsA(isA<CloudflareTurnException>()),
    );
  });

  test(
    'throws CloudflareTurnException when the response has no iceServers field',
    () {
      final mock = MockClient(
        (request) async => http.Response(jsonEncode({}), 201),
      );
      expect(
        fetchCloudflareIceServers(
          credentialsUri: Uri.parse('https://example.org/turn/credentials'),
          authorizationProvider: _authorization,
          httpClient: mock,
        ),
        throwsA(isA<CloudflareTurnException>()),
      );
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
          return http.Response(jsonEncode({'iceServers': <Object?>[]}), 201);
        });
        List<Map<String, Object?>>? servers;
        fetchCloudflareIceServers(
          credentialsUri: Uri.parse('https://example.org/turn/credentials'),
          authorizationProvider: _authorization,
          httpClient: mock,
        ).then((s) => servers = s);

        async.elapse(const Duration(seconds: 5));

        expect(calls, 2);
        expect(servers, isEmpty);
      });
    },
  );

  test('retries a 5xx and returns the servers once it succeeds', () {
    fakeAsync((async) {
      var calls = 0;
      final mock = MockClient((request) async {
        calls++;
        if (calls == 1) return http.Response('server error', 503);
        return http.Response(jsonEncode({'iceServers': <Object?>[]}), 201);
      });
      List<Map<String, Object?>>? servers;
      fetchCloudflareIceServers(
        credentialsUri: Uri.parse('https://example.org/turn/credentials'),
        authorizationProvider: _authorization,
        httpClient: mock,
      ).then((s) => servers = s);

      async.elapse(const Duration(seconds: 5));

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
          await fetchCloudflareIceServers(
            credentialsUri: Uri.parse('https://example.org/turn/credentials'),
            authorizationProvider: _authorization,
            httpClient: mock,
          );
        } catch (e) {
          error = e;
        }
      }();

      async.elapse(const Duration(seconds: 5));

      expect(calls, 1);
      expect(error, isA<CloudflareTurnException>());
    });
  });

  test('a 401 refreshes the authorization once and retries', () async {
    final refreshes = <bool>[];
    final mock = MockClient((request) async {
      if (request.headers['Authorization'] == 'Bearer fresh') {
        return http.Response(jsonEncode({'iceServers': []}), 200);
      }
      return http.Response('expired', 401);
    });
    final servers = await fetchCloudflareIceServers(
      credentialsUri: Uri.parse('https://example.org/turn/credentials'),
      authorizationProvider: ({bool refresh = false}) async {
        refreshes.add(refresh);
        return refresh ? 'Bearer fresh' : 'Bearer stale';
      },
      httpClient: mock,
    );
    expect(servers, isEmpty);
    expect(refreshes, [false, true]);
  });

  test(
    'a GatewayEnrollmentException from the provider is not retried',
    () async {
      var calls = 0;
      final mock = MockClient((request) async => http.Response('unused', 200));
      Object? error;
      try {
        await fetchCloudflareIceServers(
          credentialsUri: Uri.parse('https://example.org/turn/credentials'),
          authorizationProvider: ({bool refresh = false}) async {
            calls++;
            throw GatewayEnrollmentException('not enrolled', statusCode: 403);
          },
          httpClient: mock,
        );
      } catch (e) {
        error = e;
      }
      expect(calls, 1);
      expect(error, isA<GatewayEnrollmentException>());
    },
  );
}
