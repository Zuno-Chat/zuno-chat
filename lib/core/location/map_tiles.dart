import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import '../calls/cloudflare/calls_gateway_credentials.dart'
    show GatewayAuthorizationProvider;
import '../matrix/gateway_origin.dart';

Uri? mapTilesBaseUri(Client client) => gatewayOrigin(client, const ['tiles']);

String mapTileUrlTemplate(Uri base) => '$base/{z}/{x}/{y}.png';

Uri mapTileProbeUri(Uri base) =>
    base.replace(pathSegments: [...base.pathSegments, '0', '0', '0.png']);

class MapTilesHttpClient extends http.BaseClient {
  final GatewayAuthorizationProvider _authorization;
  final http.Client _inner;

  MapTilesHttpClient({
    required GatewayAuthorizationProvider authorization,
    http.Client? inner,
  }) : this._(authorization, inner ?? http.Client());

  MapTilesHttpClient._(this._authorization, this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers['Authorization'] = await _authorization(refresh: false);
    final response = await _inner.send(request);
    if (response.statusCode != 401) return response;
    unawaited(response.stream.drain<void>().catchError((_) {}));
    final retry = _copy(request)
      ..headers['Authorization'] = await _authorization(refresh: true);
    return _inner.send(retry);
  }

  http.Request _copy(http.BaseRequest source) {
    final copy = source is http.Abortable
        ? http.AbortableRequest(
            source.method,
            source.url,
            abortTrigger: source.abortTrigger,
          )
        : http.Request(source.method, source.url);
    copy
      ..headers.addAll(source.headers)
      ..followRedirects = source.followRedirects
      ..maxRedirects = source.maxRedirects
      ..persistentConnection = source.persistentConnection;
    if (source is http.Request) copy.bodyBytes = source.bodyBytes;
    return copy;
  }

  @override
  void close() => _inner.close();
}

Future<bool> probeMapTiles(http.Client client, Uri base) async {
  try {
    final response = await client
        .get(mapTileProbeUri(base))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return false;
    return response.headers['content-type']?.startsWith('image/') ?? false;
  } catch (_) {
    return false;
  }
}
