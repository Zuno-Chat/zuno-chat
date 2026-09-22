import 'package:matrix/matrix.dart';

import 'geo_uri.dart';

const _locationKey = 'org.matrix.msc3488.location';

Map<String, Object?> locationMessageContent(
  GeoUri geo, {
  required DateTime timestamp,
}) {
  final uri = geo.toUriString();
  return {
    'msgtype': MessageTypes.Location,
    'body': 'Location: ${geo.coordinatesLabel}',
    'geo_uri': uri,
    _locationKey: {'uri': uri, 'description': 'Location'},
    'org.matrix.msc3488.asset': {'type': 'm.self'},
    'org.matrix.msc3488.ts': timestamp.millisecondsSinceEpoch,
    'org.matrix.msc1767.text': 'Location: ${geo.coordinatesLabel}',
  };
}

GeoUri? locationOf(Event event) {
  if (event.messageType != MessageTypes.Location) return null;
  final direct = event.content.tryGet<String>('geo_uri');
  final nested = event.content
      .tryGetMap<String, Object?>(_locationKey)
      ?.tryGet<String>('uri');
  return GeoUri.tryParse(direct ?? nested);
}
