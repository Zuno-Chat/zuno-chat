import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/matrixrtc/ice_servers.dart';

import '../../../helpers/fake_matrix.dart';

Client _signedInClient() => buildTestClient(userId: '@alice:example.org')
  ..homeserver = Uri.parse('https://example.org')
  ..accessToken = 'syt_token';

void main() {
  const credentialsPath =
      '/_synapse/client/zuno/calls/cloudflare/turn/credentials';

  test('returns the module-minted ICE servers verbatim', () async {
    final client = _signedInClient();

    final servers = await resolveIceServers(
      client,
      httpClient: MockClient((request) async {
        expect(request.url.toString(), 'https://example.org$credentialsPath');
        expect(request.headers['Authorization'], 'Bearer syt_token');
        expect(request.body, isEmpty);
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

  test('an unreachable module degrades to no TURN, not an error', () async {
    final client = _signedInClient();

    final servers = await resolveIceServers(
      client,
      httpClient: MockClient((_) async => throw http.ClientException('down')),
    );

    expect(servers, isEmpty);
  });

  test('a module error response degrades to no TURN too', () async {
    final client = _signedInClient();

    final servers = await resolveIceServers(
      client,
      httpClient: MockClient((_) async => http.Response('nope', 502)),
    );

    expect(servers, isEmpty);
  });

  test('a client without an access token degrades to no TURN', () async {
    final client = buildTestClient()
      ..homeserver = Uri.parse('https://example.org');
    var requests = 0;

    final servers = await resolveIceServers(
      client,
      httpClient: MockClient((_) async {
        requests++;
        return http.Response(jsonEncode({'iceServers': []}), 200);
      }),
    );

    expect(servers, isEmpty);
    expect(requests, 0);
  });

  test('a mint that outlives its budget degrades to no TURN', () {
    fakeAsync((async) {
      final client = _signedInClient();
      List<Map<String, Object?>>? servers;

      resolveIceServers(
        client,
        httpClient: MockClient((_) => Completer<http.Response>().future),
      ).then((s) => servers = s);

      async.elapse(const Duration(seconds: 4));
      expect(servers, isNull);
      async.elapse(const Duration(seconds: 1));
      expect(servers, isEmpty);
    });
  });
}
