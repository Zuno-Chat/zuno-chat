import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/location/map_tile_cache.dart';
import 'package:zuno/core/location/map_tiles.dart';
import 'package:zuno/core/location/map_tiles_provider.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/network/user_agent.dart';
import 'package:zuno/core/platform/app_platform.dart';

import '../../helpers/fake_matrix.dart';

const _template = 'https://tiles.example.org/{z}/{x}/{y}.png';
const _credit = '© OpenStreetMap contributors';

class _TileServerClient extends MockClient {
  _TileServerClient(super.fn);

  bool closed = false;

  @override
  void close() {
    closed = true;
    super.close();
  }
}

http.Response _image() =>
    http.Response('png', 200, headers: {'content-type': 'image/png'});

http.Response _unavailable() => http.Response('', 503);

void main() {
  late List<Uri> tileRequests;
  late List<_TileServerClient> tileClients;
  late http.Response Function() tileServer;
  late int wellKnownFetches;
  late Map<String, Object?> advertised;
  late StreamController<bool> logins;
  late Client client;

  setUp(() {
    tileRequests = [];
    tileClients = [];
    tileServer = _image;
    wellKnownFetches = 0;
    advertised = {
      'im.zuno.tiles': {'url': _template, 'attribution': _credit},
    };
    logins = StreamController<bool>.broadcast();
    client = buildTestClient(
      userId: '@a:example.org',
      httpClient: MockClient((request) async {
        wellKnownFetches++;
        return http.Response(
          jsonEncode({
            'm.homeserver': {'base_url': 'https://api.example.org'},
            ...advertised,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    )..homeserver = Uri.parse('https://api.example.org');
  });

  http.Client newTileClient() {
    final tileClient = _TileServerClient((request) async {
      tileRequests.add(request.url);
      return tileServer();
    });
    tileClients.add(tileClient);
    return tileClient;
  }

  ProviderContainer listening() {
    final container = ProviderContainer(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        isLoggedInProvider.overrideWith((ref) => logins.stream),
      ],
    );
    http.runWithClient(
      () => container.listen(mapTilesProvider, (_, _) {}),
      newTileClient,
    );
    return container;
  }

  Future<MapTiles?> tiles(ProviderContainer container) =>
      container.read(mapTilesProvider.future);

  group('mapTilesProvider', () {
    test('serves the advertised tiles once a probe gets an image', () async {
      final container = listening();
      addTearDown(container.dispose);

      final served = await tiles(container);

      expect(served?.urlTemplate, _template);
      expect(served?.attribution, _credit);
      expect(served?.httpClient, same(tileClients.single));
      expect(tileRequests.map((uri) => '$uri'), [
        'https://tiles.example.org/0/0/0.png',
      ]);
    });

    test('tile requests carry the Zuno user agent', () async {
      final previous = HttpOverrides.current;
      addTearDown(() => HttpOverrides.global = previous);
      await installUserAgent(
        version: () async => '1.2.3',
        platform: AppPlatform.android,
      );
      final container = listening();
      addTearDown(container.dispose);

      final served = await tiles(container);

      expect(served?.userAgent, 'Zuno/1.2.3 (Android; im.zuno.chat)');
    });

    test('serves nothing when the probe gets no image back', () async {
      tileServer = _unavailable;
      final container = listening();
      addTearDown(container.dispose);

      expect(await tiles(container), isNull);
    });

    test(
      'serves nothing and probes nothing when no tiles are advertised',
      () async {
        advertised = {};
        final container = listening();
        addTearDown(container.dispose);

        expect(await tiles(container), isNull);
        expect(tileRequests, isEmpty);
      },
    );

    test('a new sign-in state fetches the tiles again', () async {
      final container = listening();
      addTearDown(container.dispose);
      await tiles(container);
      final fetchesBefore = wellKnownFetches;

      logins.add(true);
      await pumpEventQueue();
      await tiles(container);

      expect(wellKnownFetches, fetchesBefore + 1);
      expect(tileClients.first.closed, isTrue);
    });

    test('looks for tiles again five minutes after finding none', () {
      client.homeserver = null;
      fakeAsync((async) {
        final container = listening();
        async.flushMicrotasks();
        expect(container.read(mapTilesProvider).value, isNull);
        expect(tileClients, hasLength(1));

        async.elapse(const Duration(minutes: 4, seconds: 59));
        expect(tileClients, hasLength(1));

        async.elapse(const Duration(seconds: 1));

        expect(tileClients, hasLength(2));
        expect(tileClients.first.closed, isTrue);
        container.dispose();
      });
    });

    test('once disposed, closes its client and looks no more', () {
      client.homeserver = null;
      fakeAsync((async) {
        final container = listening();
        async.flushMicrotasks();

        container.dispose();
        async.elapse(const Duration(minutes: 10));

        expect(tileClients.single.closed, isTrue);
      });
    });
  });

  group('MapTiles', () {
    const source = TileSource(urlTemplate: _template);

    test('sends its user agent with every tile request', () {
      final tiles = MapTiles(
        source: source,
        httpClient: MockClient((_) async => _image()),
        userAgent: 'Zuno/1.2.3',
      );

      expect(tiles.tileProvider.headers['User-Agent'], 'Zuno/1.2.3');
    });

    test('without a user agent leaves the header to the platform', () {
      final tiles = MapTiles(
        source: source,
        httpClient: MockClient((_) async => _image()),
      );

      expect(tiles.tileProvider.headers, isNot(contains('User-Agent')));
    });

    test('caches tiles in the shared tile cache unless given one', () {
      final tiles = MapTiles(
        source: source,
        httpClient: MockClient((_) async => _image()),
      );

      expect(
        (tiles.tileProvider as NetworkTileProvider).cachingProvider,
        same(mapTileCache()),
      );
    });
  });
}
