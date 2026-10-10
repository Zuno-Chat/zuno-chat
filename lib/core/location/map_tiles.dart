import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import '../errors/caught_errors.dart';

const _wellKnownKey = 'im.zuno.tiles';

class TileSource {
  final String urlTemplate;
  final String? attribution;

  const TileSource({required this.urlTemplate, this.attribution});
}

Future<TileSource?> fetchTileSource(Client client) async {
  final homeserver = client.homeserver;
  if (homeserver == null) return null;
  try {
    final response = await client.httpClient.get(
      Uri.https(
        client.userID?.domain ?? homeserver.host,
        '/.well-known/matrix/client',
      ),
    );
    if (response.statusCode != 200) return null;
    final wellKnown = jsonDecode(utf8.decode(response.bodyBytes));
    if (wellKnown is! Map) return null;
    return _tileSourceFrom(wellKnown[_wellKnownKey]);
  } on FormatException {
    return null;
  } catch (error, stack) {
    reportCaught('map tile source', error, stack);
    return null;
  }
}

TileSource? _tileSourceFrom(Object? entry) {
  if (entry is! Map) return null;
  final url = entry['url'];
  if (url is! String || !_isUsableTemplate(url)) return null;
  final attribution = entry['attribution'];
  return TileSource(
    urlTemplate: url,
    attribution: attribution is String && attribution.isNotEmpty
        ? attribution
        : null,
  );
}

bool _isUsableTemplate(String url) =>
    url.startsWith('https://') &&
    url.contains('{z}') &&
    url.contains('{x}') &&
    url.contains('{y}');

Uri mapTileProbeUri(TileSource source) => Uri.parse(
  source.urlTemplate
      .replaceAll('{z}', '0')
      .replaceAll('{x}', '0')
      .replaceAll('{y}', '0'),
);

Future<bool> probeMapTiles(http.Client client, TileSource source) async {
  try {
    final response = await client
        .get(mapTileProbeUri(source))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return false;
    return response.headers['content-type']?.startsWith('image/') ?? false;
  } catch (error, stack) {
    reportCaught('probe map tiles', error, stack);
    return false;
  }
}
