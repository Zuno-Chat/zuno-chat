import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zuno/core/location/map_tile_cache.dart';
import 'package:zuno/core/location/map_tiles.dart';
import 'package:zuno/core/location/map_tiles_provider.dart';
import 'package:zuno/core/network/app_http_client.dart';
import 'package:zuno/core/network/app_http_overrides.dart';
import 'package:zuno/core/platform/app_platform.dart';

import '../../helpers/fake_http.dart';
import '../../helpers/hybrid_fake_async.dart';
import '../../helpers/pump_until.dart';

const _template = 'https://tiles.example.org/{z}/{x}/{y}.png';
const _credit = 'OpenStreetMap contributors';

http.Response _image() =>
    http.Response('png', 200, headers: {'content-type': 'image/png'});

http.Response _unavailable() => http.Response('', 503);

void main() {
  late List<Uri> tileRequests;
  late List<FakeHttpClient> tileClients;
  late http.Response Function() tileServer;

  setUp(() {
    tileRequests = [];
    tileClients = [];
    tileServer = _image;
  });

  http.Client newTileClient() {
    final tileClient = FakeHttpClient((request) async {
      tileRequests.add(request.url);
      return tileServer();
    });
    tileClients.add(tileClient);
    return tileClient;
  }

  ProviderContainer listening() {
    appHttpClientFactory = (_) => newTileClient();
    final container = ProviderContainer();
    container.listen(mapTilesProvider, (_, _) {});
    return container;
  }

  Future<MapTiles?> tiles(ProviderContainer container) =>
      container.read(mapTilesProvider.future);

  group('mapTilesProvider', () {
    test('serves Zuno\'s credited tiles, whatever the homeserver, once a '
        'probe gets an image', () async {
      final container = listening();
      addTearDown(container.dispose);

      final served = await tiles(container);

      expect(served?.urlTemplate, 'https://maps.zuno.chat/{z}/{x}/{y}');
      expect(served?.attribution, 'MapTiler © OpenStreetMap contributors');
      expect(served?.httpClient, same(tileClients.single));
      expect(tileRequests.map((uri) => '$uri'), [
        'https://maps.zuno.chat/0/0/0',
      ]);
    });

    test('tile requests carry the Zuno user agent', () async {
      final previous = HttpOverrides.current;
      addTearDown(() => HttpOverrides.global = previous);
      await installAppHttpOverrides(
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
      expect(tileRequests, hasLength(1));
    });

    test('looks for tiles again five minutes after finding none', () {
      tileServer = _unavailable;
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
      tileServer = _unavailable;
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
    const source = TileSource(urlTemplate: _template, attribution: _credit);

    test('sends its user agent with every tile request', () {
      final tiles = MapTiles(
        source: source,
        httpClient: FakeHttpClient((_) async => _image()),
        userAgent: 'Zuno/1.2.3',
      );

      expect(tiles.tileProvider.headers['User-Agent'], 'Zuno/1.2.3');
    });

    test('without a user agent leaves the header to the platform', () {
      final tiles = MapTiles(
        source: source,
        httpClient: FakeHttpClient((_) async => _image()),
      );

      expect(tiles.tileProvider.headers, isNot(contains('User-Agent')));
    });

    test('live maps keep tiles in memory only, with the same user agent', () {
      final tiles = MapTiles(
        source: source,
        httpClient: FakeHttpClient((_) async => _image()),
        userAgent: 'Zuno/1.2.3',
      );

      final provider = tiles.ephemeralTileProvider as NetworkTileProvider;
      expect(provider.cachingProvider, isA<DisabledMapCachingProvider>());
      expect(provider.headers['User-Agent'], 'Zuno/1.2.3');
    });

    MapTiles answering(FakeHttpHandler answer) => MapTiles(
      source: source,
      httpClient: FakeHttpClient(answer),
      cachingProvider: const DisabledMapCachingProvider(),
    );

    group('a tile that fails to load', () {
      final tile = Uri.parse('https://tiles.example.org/16/0/0.png');

      Future<http.StreamedResponse> fetch(
        MapTiles tiles, {
        Future<void>? dropped,
      }) => tiles.tileClient.send(
        http.AbortableRequest(
          'GET',
          tile,
          abortTrigger: dropped ?? Completer<void>().future,
        ),
      );

      test('is tried again, each wait at most double the last and 15 s, '
          'until it arrives', () {
        fakeAsync((async) {
          final answers = <http.Response Function()>[
            () => throw http.ClientException('offline'),
            _unavailable,
            () => http.Response('', 429),
            () => http.Response('', 502),
            () => http.Response('', 408),
            () => throw http.ClientException('offline'),
            _image,
          ];
          final sentAt = <Duration>[];
          final tiles = answering((_) async {
            sentAt.add(async.elapsed);
            return answers[sentAt.length - 1]();
          });

          final response = async.waitFor(
            fetch(tiles),
            elapsing: const Duration(minutes: 1),
          );

          expect(response.statusCode, 200);
          expect(sentAt, hasLength(answers.length));
          const longestWaits = [1, 2, 4, 8, 15, 15];
          for (var i = 1; i < sentAt.length; i++) {
            expect(
              sentAt[i] - sentAt[i - 1],
              lessThanOrEqualTo(Duration(seconds: longestWaits[i - 1])),
            );
          }
        });
      });

      test('is tried again when it breaks off mid-download', () {
        fakeAsync((async) {
          var sent = 0;
          final tiles = MapTiles(
            source: source,
            httpClient: MockClient.streaming((_, _) async {
              sent++;
              return http.StreamedResponse(
                sent == 1
                    ? Stream<List<int>>.error(http.ClientException('dropped'))
                    : Stream.value(utf8.encode('png')),
                200,
              );
            }),
          );

          final response = async.waitFor(
            fetch(tiles),
            elapsing: const Duration(seconds: 1),
          );

          expect(sent, 2);
          expect(async.waitFor(response.stream.bytesToString()), 'png');
        });
      });

      test('is not tried again when the server refuses it', () {
        fakeAsync((async) {
          var sent = 0;
          final tiles = answering((_) async {
            sent++;
            return http.Response('', 403);
          });

          final response = async.waitFor(
            fetch(tiles),
            elapsing: const Duration(minutes: 1),
          );

          expect(response.statusCode, 403);
          expect(sent, 1);
        });
      });

      test('without a way to cancel it, goes out only once', () {
        fakeAsync((async) {
          var sent = 0;
          final tiles = answering((_) async {
            sent++;
            return _unavailable();
          });

          final response = async.waitFor(
            tiles.tileClient.get(tile),
            elapsing: const Duration(minutes: 1),
          );

          expect(response.statusCode, 503);
          expect(sent, 1);
        });
      });

      test('stops waiting and is no longer tried once the map drops it', () {
        fakeAsync((async) {
          var sent = 0;
          final tiles = answering((_) async {
            sent++;
            throw http.ClientException('offline');
          });
          final dropped = Completer<void>();
          final response = fetch(tiles, dropped: dropped.future);
          async.flushMicrotasks();

          dropped.complete();

          expect(
            () => async.waitFor(response),
            throwsA(isA<http.RequestAbortedException>()),
          );
          expect(async.pendingTimers, isEmpty);
          async.elapse(const Duration(minutes: 1));
          expect(sent, 1);
        });
      });
    });

    group('through the map', () {
      final layer = TileLayer(urlTemplate: _template);

      void show(
        TileProvider provider,
        TileCoordinates tile,
        Future<void> dropped,
      ) => resolveImage(
        provider.getImageWithCancelLoadingSupport(tile, layer, dropped),
      ).ignore();

      tearDown(() => PaintingBinding.instance.imageCache.clear());

      testWidgets('both tile providers retry a tile that fails', (
        tester,
      ) async {
        final sent = <Uri>[];
        final tiles = answering((request) async {
          sent.add(request.url);
          return _unavailable();
        });
        final dropped = Completer<void>();
        show(
          tiles.tileProvider,
          const TileCoordinates(0, 0, 16),
          dropped.future,
        );
        show(
          tiles.ephemeralTileProvider,
          const TileCoordinates(1, 0, 16),
          dropped.future,
        );

        await tester.pump(const Duration(seconds: 1));

        final asked = sent.toSet();
        expect(asked, hasLength(2));
        for (final url in asked) {
          expect(
            sent.where((sentTo) => sentTo == url),
            hasLength(greaterThan(1)),
          );
        }
        dropped.complete();
        await tester.pump();
      });

      testWidgets('two maps showing one tile share its download, and it is '
          'cancelled only once neither shows it', (tester) async {
        var sent = 0;
        final tiles = answering((_) async {
          sent++;
          return _unavailable();
        });
        const tile = TileCoordinates(2, 0, 16);
        final preview = Completer<void>();
        final fullMap = Completer<void>();
        show(tiles.ephemeralTileProvider, tile, preview.future);
        show(tiles.tileProvider, tile, fullMap.future);
        await tester.pump();
        expect(sent, 1);

        preview.complete();
        await tester.pump(const Duration(seconds: 10));
        expect(sent, greaterThan(1));

        final sentBefore = sent;
        fullMap.complete();
        await tester.pump(const Duration(minutes: 1));
        expect(sent, sentBefore);
      });
    });

    test('caches tiles in the shared tile cache unless given one', () {
      final tiles = MapTiles(
        source: source,
        httpClient: FakeHttpClient((_) async => _image()),
      );

      expect(
        (tiles.tileProvider as NetworkTileProvider).cachingProvider,
        same(mapTileCache()),
      );
    });
  });
}
