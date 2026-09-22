import 'package:flutter_map/flutter_map.dart';

import '../errors/best_effort.dart';

const _maxTileCacheBytes = 64 * 1024 * 1024;

MapCachingProvider mapTileCache() =>
    BuiltInMapCachingProvider.getOrCreateInstance(
      maxCacheSize: _maxTileCacheBytes,
    );

Future<void> purgeMapTileCache() => runBestEffort(
  () => BuiltInMapCachingProvider.getOrCreateInstance().destroy(
    deleteCache: true,
  ),
  label: 'purge map tile cache',
);
