import 'package:http/http.dart' as http;
import 'package:zuno_http/zuno_http.dart' show DeadlineRequest;

import '../errors/caught_errors.dart';

class TileSource {
  final String urlTemplate;
  final String attribution;

  const TileSource({required this.urlTemplate, required this.attribution});
}

const zunoTileSource = TileSource(
  urlTemplate: 'https://maps.zuno.chat/{z}/{x}/{y}',
  attribution: 'MapTiler © OpenStreetMap contributors',
);

Uri mapTileProbeUri(TileSource source) => Uri.parse(
  source.urlTemplate
      .replaceAll('{z}', '0')
      .replaceAll('{x}', '0')
      .replaceAll('{y}', '0'),
);

const _probeDeadline = Duration(seconds: 10);

Future<bool> probeMapTiles(http.Client client, TileSource source) async {
  try {
    final response = await http.Response.fromStream(
      await client.send(
        DeadlineRequest(
          'GET',
          mapTileProbeUri(source),
          thinkTime: _probeDeadline,
        ),
      ),
    );
    if (response.statusCode != 200) return false;
    return response.headers['content-type']?.startsWith('image/') ?? false;
  } catch (error, stack) {
    reportCaught('probe map tiles', error, stack);
    return false;
  }
}
