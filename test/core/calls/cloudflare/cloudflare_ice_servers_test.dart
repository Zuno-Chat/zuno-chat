import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/calls/cloudflare/cloudflare_ice_servers.dart';

import '../../../helpers/caught_reports.dart';
import '../../../helpers/fake_http.dart';
import '../../../helpers/fake_matrix.dart';

Client _signedInClient() => buildTestClient(userId: '@alice:example.org')
  ..homeserver = Uri.parse('https://example.org')
  ..accessToken = 'syt_token';

void main() {
  const credentialsPath =
      '/_synapse/client/zuno/calls/cloudflare/turn/credentials';

  test('returns the module-minted ICE servers verbatim', () async {
    final client = _signedInClient();

    final servers = await resolveCloudflareIceServers(
      client,
      httpClient: FakeHttpClient((request) async {
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

  test('a module error response degrades to no TURN', () async {
    final client = _signedInClient();

    final servers = await resolveCloudflareIceServers(
      client,
      httpClient: FakeHttpClient((_) async => http.Response('nope', 502)),
    );

    expect(servers, isEmpty);
  });

  test('a gone TURN route or a module 5xx degrades to no TURN without a '
      'report', () async {
    final client = _signedInClient();
    for (final response in [
      http.Response(jsonEncode({'errcode': 'M_UNRECOGNIZED'}), 404),
      http.Response('nope', 502),
    ]) {
      final reports = await reportsDuring(() async {
        expect(
          await resolveCloudflareIceServers(
            client,
            httpClient: FakeHttpClient((_) async => response),
          ),
          isEmpty,
        );
      });

      expect(reports, isEmpty);
    }
  });

  test('an answer without ICE servers is reported', () async {
    final client = _signedInClient();

    final reports = await reportsDuring(
      () => resolveCloudflareIceServers(
        client,
        httpClient: FakeHttpClient(
          (_) async => http.Response(jsonEncode({}), 200),
        ),
      ),
    );

    expect(reports, ['mint TURN credentials']);
  });

  test('a client without an access token degrades to no TURN', () async {
    final client = buildTestClient()
      ..homeserver = Uri.parse('https://example.org');
    var requests = 0;

    final servers = await resolveCloudflareIceServers(
      client,
      httpClient: FakeHttpClient((_) async {
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

      resolveCloudflareIceServers(
        client,
        httpClient: FakeHttpClient((_) => Completer<http.Response>().future),
      ).then((s) => servers = s);

      async.elapse(const Duration(seconds: 4));
      expect(servers, isNull);
      async.elapse(const Duration(seconds: 1));
      expect(servers, isEmpty);
    });
  });
}
