import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/location/map_tile_cache.dart';

const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');

const _url = 'https://tiles.example.org/1/0/0.png';

final _tile = Uint8List.fromList(List.generate(64, (i) => i));

CachedMapTileMetadata _freshForADay() => CachedMapTileMetadata(
  staleAt: DateTime.timestamp().add(const Duration(days: 1)),
  lastModified: null,
  etag: null,
);

Future<CachedMapTile?> _readBack(MapCachingProvider cache, String url) async {
  for (var i = 0; i < 100; i++) {
    final cached = await cache.getTile(url);
    if (cached != null) return cached;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory cacheRoot;

  setUp(() {
    cacheRoot = Directory.systemTemp.createTempSync('zuno_map_tiles');
    messenger.setMockMethodCallHandler(
      _pathProvider,
      (call) async =>
          call.method == 'getApplicationCacheDirectory' ? cacheRoot.path : null,
    );
  });

  tearDown(() async {
    await purgeMapTileCache();
    messenger.setMockMethodCallHandler(_pathProvider, null);
    if (cacheRoot.existsSync()) cacheRoot.deleteSync(recursive: true);
  });

  test('keeps tiles in the app cache directory', () async {
    final cache = mapTileCache();

    await cache.putTile(url: _url, metadata: _freshForADay(), bytes: _tile);

    expect((await _readBack(cache, _url))?.bytes, _tile);
    expect(Directory('${cacheRoot.path}/fm_cache').existsSync(), isTrue);
  });

  test('tells flutter_map that tiles can be cached', () {
    expect(mapTileCache().isSupported, isTrue);
  });

  test('a purge deletes the cached tiles', () async {
    final cache = mapTileCache();
    await cache.putTile(url: _url, metadata: _freshForADay(), bytes: _tile);
    expect((await _readBack(cache, _url))?.bytes, _tile);

    await purgeMapTileCache();

    expect(await mapTileCache().getTile(_url), isNull);
  });

  test('a cache handed out before a purge keeps caching after it', () async {
    final cache = mapTileCache();
    await cache.putTile(url: _url, metadata: _freshForADay(), bytes: _tile);
    expect((await _readBack(cache, _url))?.bytes, _tile);

    await purgeMapTileCache();
    const later = 'https://tiles.example.org/1/1/0.png';
    await cache.putTile(url: later, metadata: _freshForADay(), bytes: _tile);

    expect((await _readBack(cache, later))?.bytes, _tile);
  });

  test('a purge with nothing cached yet completes', () async {
    await expectLater(purgeMapTileCache(), completes);
  });
}
