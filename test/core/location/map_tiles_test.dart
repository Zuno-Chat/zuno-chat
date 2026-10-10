import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:zuno/core/location/map_tiles.dart';

import '../../helpers/fake_matrix.dart';

const _template =
    'https://api.maptiler.com/maps/streets-v2/256/{z}/{x}/{y}.png?key=k1';
const _credit = 'MapTiler © OpenStreetMap contributors';

http.Response _wellKnown(Map<String, Object?> extra) => http.Response(
  jsonEncode({
    'm.homeserver': {'base_url': 'https://api.example.org'},
    ...extra,
  }),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  group('tile source', () {
    Future<TileSource?> sourceAnswering(MockClientHandler handler) =>
        fetchTileSource(
          buildTestClient(
            userId: '@a:example.org',
            httpClient: MockClient(handler),
          )..homeserver = Uri.parse('https://api.example.org'),
        );

    Future<TileSource?> sourceFrom(http.Response response) =>
        sourceAnswering((_) async => response);

    test(
      'comes from the server name\'s well-known, not the API host',
      () async {
        Uri? asked;
        await sourceAnswering((request) async {
          asked = request.url;
          return _wellKnown({
            'im.zuno.tiles': {'url': _template},
          });
        });

        expect(
          asked.toString(),
          'https://example.org/.well-known/matrix/client',
        );
      },
    );

    test('carries the template and the credit to show', () async {
      final source = await sourceFrom(
        _wellKnown({
          'im.zuno.tiles': {'url': _template, 'attribution': _credit},
        }),
      );

      expect(source?.urlTemplate, _template);
      expect(source?.attribution, _credit);
    });

    test('a missing credit leaves the map uncredited', () async {
      final source = await sourceFrom(
        _wellKnown({
          'im.zuno.tiles': {'url': _template},
        }),
      );

      expect(source?.urlTemplate, _template);
      expect(source?.attribution, isNull);
    });

    for (final (reason, response) in [
      ('when the server advertises no tiles', _wellKnown({})),
      (
        'for a template sent in the clear',
        _wellKnown({
          'im.zuno.tiles': {'url': 'http://tiles.example.org/{z}/{x}/{y}.png'},
        }),
      ),
      (
        'for a template missing a coordinate',
        _wellKnown({
          'im.zuno.tiles': {'url': 'https://tiles.example.org/{z}/{x}.png'},
        }),
      ),
      (
        'when the entry has the wrong shape',
        _wellKnown({'im.zuno.tiles': _template}),
      ),
      ('when the well-known is not JSON', http.Response('<html>', 200)),
    ]) {
      test('is none $reason', () async {
        expect(await sourceFrom(response), isNull);
      });
    }

    test('is none when the well-known cannot be reached', () async {
      final source = await sourceAnswering(
        (_) async => throw const SocketException('x'),
      );

      expect(source, isNull);
    });

    test('is none before a homeserver is known', () async {
      expect(await fetchTileSource(buildTestClient()), isNull);
    });
  });

  group('availability probe', () {
    const source = TileSource(urlTemplate: _template);

    test('asks for the world tile, keeping the key', () {
      expect(
        mapTileProbeUri(source).toString(),
        'https://api.maptiler.com/maps/streets-v2/256/0/0/0.png?key=k1',
      );
    });

    test('is available when the source answers with an image', () async {
      final client = MockClient(
        (_) async =>
            http.Response('png', 200, headers: {'content-type': 'image/png'}),
      );

      expect(await probeMapTiles(client, source), isTrue);
    });

    for (final (reason, answer) in <(String, MockClientHandler)>[
      ('the key is refused', (_) async => http.Response('Invalid key', 403)),
      (
        'something other than a tile comes back',
        (_) async => http.Response(
          '<html>',
          200,
          headers: {'content-type': 'text/html'},
        ),
      ),
      (
        'the host cannot be reached',
        (_) async => throw const SocketException('x'),
      ),
    ]) {
      test('is unavailable when $reason', () async {
        expect(await probeMapTiles(MockClient(answer), source), isFalse);
      });
    }
  });
}
