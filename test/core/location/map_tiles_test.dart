import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:zuno/core/location/map_tiles.dart';

import '../../helpers/fake_http.dart';

const _template =
    'https://api.maptiler.com/maps/streets-v2/256/{z}/{x}/{y}.png?key=k1';

void main() {
  group('availability probe', () {
    const source = TileSource(urlTemplate: _template, attribution: 'credit');

    test('asks for the world tile, keeping the key', () {
      expect(
        mapTileProbeUri(source).toString(),
        'https://api.maptiler.com/maps/streets-v2/256/0/0/0.png?key=k1',
      );
    });

    test('is available when the source answers with an image', () async {
      final client = FakeHttpClient(
        (_) async =>
            http.Response('png', 200, headers: {'content-type': 'image/png'}),
      );

      expect(await probeMapTiles(client, source), isTrue);
    });

    for (final (reason, answer) in <(String, FakeHttpHandler)>[
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
        expect(await probeMapTiles(FakeHttpClient(answer), source), isFalse);
      });
    }
  });
}
