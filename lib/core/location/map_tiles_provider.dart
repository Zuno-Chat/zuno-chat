import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../errors/backoff.dart';
import '../errors/connection_error.dart';
import '../network/app_http_client.dart';
import '../network/app_http_overrides.dart';
import 'map_tile_cache.dart';
import 'map_tiles.dart';

class MapTiles {
  final TileSource source;
  final http.Client httpClient;
  final String? userAgent;
  final MapCachingProvider? cachingProvider;

  MapTiles({
    required this.source,
    required this.httpClient,
    this.userAgent,
    this.cachingProvider,
  });

  String get urlTemplate => source.urlTemplate;

  String get attribution => source.attribution;

  late final http.Client tileClient = _TileRetries(httpClient);

  late final TileProvider tileProvider = _SharedTiles(
    this,
    cachingProvider: cachingProvider ?? mapTileCache(),
  );

  late final TileProvider ephemeralTileProvider = _SharedTiles(
    this,
    cachingProvider: const DisabledMapCachingProvider(),
  );

  final _shown = <String, _TileShown>{};

  Future<void> _droppedEverywhere(String url, Future<void> dropped) {
    final shown = _shown[url] ??= _TileShown();
    shown.maps++;
    unawaited(
      dropped.then((_) {
        if (--shown.maps > 0) return;
        _shown.remove(url);
        shown.dropped.complete();
      }),
    );
    return shown.dropped.future;
  }
}

class _TileShown {
  var maps = 0;
  final dropped = Completer<void>();
}

class _SharedTiles extends NetworkTileProvider {
  _SharedTiles(this._tiles, {required super.cachingProvider})
    : super(
        headers: {'User-Agent': ?_tiles.userAgent},
        httpClient: _tiles.tileClient,
        silenceExceptions: true,
      );

  final MapTiles _tiles;

  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) => super.getImageWithCancelLoadingSupport(
    coordinates,
    options,
    _tiles._droppedEverywhere(getTileUrl(coordinates, options), cancelLoading),
  );
}

class _TileRetries extends http.BaseClient {
  _TileRetries(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final dropped = switch (request) {
      http.Abortable(:final abortTrigger?) => abortTrigger,
      _ => null,
    };
    if (dropped == null) return _inner.send(request);
    var isDropped = false;
    Timer? waiting;
    var attempt = Completer<void>();
    dropped.whenComplete(() {
      isDropped = true;
      waiting?.cancel();
      if (!attempt.isCompleted) attempt.complete();
    }).ignore();
    for (var retry = 1; !isDropped; retry++) {
      try {
        final response = await _inner.send(
          http.AbortableRequest(
            request.method,
            request.url,
            abortTrigger: attempt.future,
          )..headers.addAll(request.headers),
        );
        if (!_isTransient(response.statusCode)) {
          return _buffered(response, await response.stream.toBytes());
        }
        unawaited(response.stream.listen(null).cancel().catchError((_) {}));
      } on http.RequestAbortedException {
        rethrow;
      } catch (error) {
        if (!isConnectionError(error)) rethrow;
      }
      if (isDropped) break;
      waiting = Timer(
        backoffDelay(
          retry,
          baseDelay: _firstRetryWait,
          maxDelay: _longestRetryWait,
        ),
        attempt.complete,
      );
      await attempt.future;
      attempt = Completer<void>();
    }
    throw http.RequestAbortedException(request.url);
  }
}

http.StreamedResponse _buffered(
  http.StreamedResponse response,
  Uint8List body,
) => http.StreamedResponse(
  http.ByteStream.fromBytes(body),
  response.statusCode,
  contentLength: body.length,
  request: response.request,
  headers: response.headers,
  isRedirect: response.isRedirect,
  persistentConnection: response.persistentConnection,
  reasonPhrase: response.reasonPhrase,
);

const _reprobeAfter = Duration(minutes: 5);
const _firstRetryWait = Duration(seconds: 1);
const _longestRetryWait = Duration(seconds: 15);

bool _isTransient(int status) =>
    status == 408 || status == 429 || status >= 500;

final mapTilesProvider = FutureProvider<MapTiles?>((ref) async {
  final httpClient = appHttpClient(HttpClientKind.service);
  ref.onDispose(httpClient.close);
  if (await probeMapTiles(httpClient, zunoTileSource)) {
    return MapTiles(
      source: zunoTileSource,
      httpClient: httpClient,
      userAgent: appUserAgent,
    );
  }
  final timer = Timer(_reprobeAfter, ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return null;
});
