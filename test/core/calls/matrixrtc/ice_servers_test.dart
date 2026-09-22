import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:zuno/core/calls/matrixrtc/ice_servers.dart';

import '../../../helpers/fake_matrix.dart';

Future<String> _authorization({bool refresh = false}) async =>
    'Bearer syt_token';

void main() {
  test('returns the gateway-minted ICE servers verbatim', () async {
    final client = buildTestClient(userId: '@alice:example.org')
      ..homeserver = Uri.parse('https://example.org')
      ..accessToken = 'syt_token';

    final servers = await resolveIceServers(
      client,
      authorizationProvider: _authorization,
      httpClient: MockClient((request) async {
        expect(request.url.toString(), 'https://example.org/turn/credentials');
        expect(request.headers['Authorization'], 'Bearer syt_token');
        return http.Response(
          jsonEncode({
            'iceServers': [
              {'urls': 'stun:stun.example.org:3478'},
              {
                'urls': 'turn:turn.example.org:3478?transport=udp',
                'username': 'u1',
                'credential': 'c1',
              },
            ],
          }),
          200,
        );
      }),
    );

    expect(servers, hasLength(2));
    expect(servers.last['username'], 'u1');
    expect(servers.last['credential'], 'c1');
  });

  test('an unreachable gateway degrades to no TURN, not an error', () async {
    final client = buildTestClient(userId: '@alice:example.org')
      ..homeserver = Uri.parse('https://example.org')
      ..accessToken = 'syt_token';

    final servers = await resolveIceServers(
      client,
      authorizationProvider: _authorization,
      httpClient: MockClient((_) async => throw http.ClientException('down')),
    );

    expect(servers, isEmpty);
  });

  test('a gateway error response degrades to no TURN too', () async {
    final client = buildTestClient(userId: '@alice:example.org')
      ..homeserver = Uri.parse('https://example.org')
      ..accessToken = 'syt_token';

    final servers = await resolveIceServers(
      client,
      authorizationProvider: _authorization,
      httpClient: MockClient((_) async => http.Response('nope', 502)),
    );

    expect(servers, isEmpty);
  });

  test(
    'an authorization failure degrades to no TURN rather than throwing',
    () async {
      final client = buildTestClient()
        ..homeserver = Uri.parse('https://example.org');

      final servers = await resolveIceServers(
        client,
        authorizationProvider: ({bool refresh = false}) async =>
            throw StateError('Not logged in'),
      );

      expect(servers, isEmpty);
    },
  );
}
