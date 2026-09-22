import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:zuno/core/location/map_tiles.dart';

import '../../helpers/fake_matrix.dart';

void main() {
  group('tile root', () {
    test('hangs off the homeserver host', () {
      final client = buildTestClient()
        ..homeserver = Uri.parse('https://example.org');

      expect(mapTilesBaseUri(client).toString(), 'https://example.org/tiles');
    });

    test('carries a non-default port and drops a path prefix', () {
      final client = buildTestClient()
        ..homeserver = Uri.parse('https://example.org:8448/matrix');

      expect(
        mapTilesBaseUri(client).toString(),
        'https://example.org:8448/tiles',
      );
    });

    test('is absent rather than guessed when no homeserver is set', () {
      expect(mapTilesBaseUri(buildTestClient()), isNull);
    });

    test('template and probe address the same root', () {
      final base = Uri.parse('https://example.org/tiles');

      expect(
        mapTileUrlTemplate(base),
        'https://example.org/tiles/{z}/{x}/{y}.png',
      );
      expect(
        mapTileProbeUri(base).toString(),
        'https://example.org/tiles/0/0/0.png',
      );
    });
  });

  group('authenticated tile client', () {
    final url = Uri.parse('https://example.org/tiles/1/2/3.png');

    test('sends the gateway token as a bearer', () async {
      String? seen;
      final client = MapTilesHttpClient(
        authorization: ({bool refresh = false}) async => 'Bearer gw_1',
        inner: MockClient((request) async {
          seen = request.headers['Authorization'];
          return http.Response('png', 200);
        }),
      );

      final response = await client.get(url);

      expect(response.statusCode, 200);
      expect(seen, 'Bearer gw_1');
    });

    test('re-enrolls once and retries on a 401', () async {
      final tokensSent = <String?>[];
      var refreshes = 0;
      final client = MapTilesHttpClient(
        authorization: ({bool refresh = false}) async {
          if (refresh) refreshes++;
          return refresh ? 'Bearer gw_2' : 'Bearer gw_1';
        },
        inner: MockClient((request) async {
          tokensSent.add(request.headers['Authorization']);
          return request.headers['Authorization'] == 'Bearer gw_2'
              ? http.Response('png', 200)
              : http.Response('', 401);
        }),
      );

      final response = await client.get(url);

      expect(response.statusCode, 200);
      expect(refreshes, 1);
      expect(tokensSent, ['Bearer gw_1', 'Bearer gw_2']);
    });

    test('keeps the retry abortable, so a stale tile can still be cancelled '
        'mid-refresh', () async {
      final abort = Completer<void>();
      http.BaseRequest? retried;
      final client = MapTilesHttpClient(
        authorization: ({bool refresh = false}) async =>
            refresh ? 'Bearer gw_2' : 'Bearer gw_1',
        inner: MockClient.streaming((request, _) async {
          if (request.headers['Authorization'] != 'Bearer gw_2') {
            return http.StreamedResponse(const Stream<List<int>>.empty(), 401);
          }
          retried = request;
          return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
        }),
      );

      await client.send(
        http.AbortableRequest('GET', url, abortTrigger: abort.future),
      );

      expect(retried, isA<http.Abortable>());
      expect((retried! as http.Abortable).abortTrigger, same(abort.future));
    });

    test('gives up after one retry instead of looping', () async {
      var requests = 0;
      final client = MapTilesHttpClient(
        authorization: ({bool refresh = false}) async => 'Bearer stale',
        inner: MockClient((_) async {
          requests++;
          return http.Response('', 401);
        }),
      );

      final response = await client.get(url);

      expect(response.statusCode, 401);
      expect(requests, 2);
    });
  });

  group('availability probe', () {
    final base = Uri.parse('https://example.org/tiles');

    test('is available when the proxy answers with an image', () async {
      final client = MockClient(
        (_) async =>
            http.Response('png', 200, headers: {'content-type': 'image/png'}),
      );

      expect(await probeMapTiles(client, base), isTrue);
    });

    test('is unavailable when the route does not exist', () async {
      final client = MockClient((_) async => http.Response('nope', 404));

      expect(await probeMapTiles(client, base), isFalse);
    });

    test(
      'is unavailable when something other than a tile comes back',
      () async {
        final client = MockClient(
          (_) async => http.Response(
            '<html>',
            200,
            headers: {'content-type': 'text/html'},
          ),
        );

        expect(await probeMapTiles(client, base), isFalse);
      },
    );

    test('is unavailable when the host cannot be reached', () async {
      final client = MockClient((_) async => throw const SocketException('x'));

      expect(await probeMapTiles(client, base), isFalse);
    });
  });
}
