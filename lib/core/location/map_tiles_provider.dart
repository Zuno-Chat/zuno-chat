import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../matrix/matrix_client_provider.dart';
import 'map_tile_cache.dart';
import 'map_tiles.dart';

class MapTiles {
  final TileSource source;
  final http.Client httpClient;
  final MapCachingProvider? cachingProvider;

  MapTiles({
    required this.source,
    required this.httpClient,
    this.cachingProvider,
  });

  String get urlTemplate => source.urlTemplate;

  String? get attribution => source.attribution;

  late final TileProvider tileProvider = NetworkTileProvider(
    httpClient: httpClient,
    cachingProvider: cachingProvider ?? mapTileCache(),
    silenceExceptions: true,
  );
}

const _reprobeAfter = Duration(minutes: 5);

final mapTilesProvider = FutureProvider<MapTiles?>((ref) async {
  final client = ref.watch(matrixClientProvider);
  ref.watch(isLoggedInProvider);
  final httpClient = http.Client();
  ref.onDispose(httpClient.close);
  final source = await fetchTileSource(client);
  if (source != null && await probeMapTiles(httpClient, source)) {
    return MapTiles(source: source, httpClient: httpClient);
  }
  final timer = Timer(_reprobeAfter, ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return null;
});
