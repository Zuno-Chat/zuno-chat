import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../calls/cloudflare/calls_gateway_credentials.dart';
import '../matrix/matrix_client_provider.dart';
import 'map_tile_cache.dart';
import 'map_tiles.dart';

class MapTiles {
  final Uri base;
  final http.Client httpClient;
  final MapCachingProvider? cachingProvider;

  MapTiles({
    required this.base,
    required this.httpClient,
    this.cachingProvider,
  });

  String get urlTemplate => mapTileUrlTemplate(base);

  late final TileProvider tileProvider = NetworkTileProvider(
    httpClient: httpClient,
    cachingProvider: cachingProvider ?? mapTileCache(),
    silenceExceptions: true,
  );
}

final mapTilesProvider = Provider<MapTiles?>((ref) {
  final client = ref.watch(matrixClientProvider);
  ref.watch(isLoggedInProvider);
  final base = mapTilesBaseUri(client);
  if (base == null) return null;
  final credentials = CallsGatewayCredentials(client: client);
  final httpClient = MapTilesHttpClient(
    authorization: credentials.authorization,
  );
  ref.onDispose(() {
    httpClient.close();
    credentials.close();
  });
  return MapTiles(base: base, httpClient: httpClient);
});

const _reprobeAfter = Duration(minutes: 5);

final mapTilesAvailableProvider = FutureProvider<bool>((ref) async {
  final tiles = ref.watch(mapTilesProvider);
  if (tiles == null) return false;
  final available = await probeMapTiles(tiles.httpClient, tiles.base);
  if (!available) {
    final timer = Timer(_reprobeAfter, ref.invalidateSelf);
    ref.onDispose(timer.cancel);
  }
  return available;
});
