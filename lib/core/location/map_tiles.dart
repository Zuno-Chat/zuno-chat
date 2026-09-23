import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

const _wellKnownKey = 'im.zuno.tiles';

class TileSource {
  final String urlTemplate;
  final String? attribution;

  const TileSource({required this.urlTemplate, this.attribution});
}

Future<TileSource?> fetchTileSource(Client client) async {
  if (client.homeserver == null) return null;
  try {
    final wellKnown = await client.getWellknown(cacheLifetime: Duration.zero);
    return _tileSourceFrom(wellKnown.additionalProperties[_wellKnownKey]);
  } catch (_) {
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
  } catch (_) {
    return false;
  }
}
