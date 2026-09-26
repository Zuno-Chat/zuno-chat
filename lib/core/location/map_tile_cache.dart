import 'dart:typed_data';

import 'package:flutter_map/flutter_map.dart';

import '../errors/best_effort.dart';

const _maxTileCacheBytes = 64 * 1024 * 1024;

BuiltInMapCachingProvider _currentCache() =>
    BuiltInMapCachingProvider.getOrCreateInstance(
      maxCacheSize: _maxTileCacheBytes,
    );

class _SharedMapTileCache implements MapCachingProvider {
  const _SharedMapTileCache();

  @override
  bool get isSupported => _currentCache().isSupported;

  @override
  Future<CachedMapTile?> getTile(String url) => _currentCache().getTile(url);

  @override
  Future<void> putTile({
    required String url,
    required CachedMapTileMetadata metadata,
    Uint8List? bytes,
  }) => _currentCache().putTile(url: url, metadata: metadata, bytes: bytes);
}

MapCachingProvider mapTileCache() => const _SharedMapTileCache();

Future<void> purgeMapTileCache() => runBestEffort(
  () => _currentCache().destroy(deleteCache: true),
  label: 'purge map tile cache',
);
