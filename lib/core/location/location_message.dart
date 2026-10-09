import 'package:matrix/matrix.dart';

import 'geo_uri.dart';

const _locationKey = 'org.matrix.msc3488.location';

Future<String?> sendLocationPin(
  Room room,
  GeoUri geo, {
  required DateTime at,
}) => room.sendLocation(
  'Location: ${geo.coordinatesLabel}',
  geo.toUriString(),
  ts: at,
);

GeoUri? locationOf(Event event) {
  if (event.messageType != MessageTypes.Location) return null;
  final direct = event.content.tryGet<String>('geo_uri');
  final nested = event.content
      .tryGetMap<String, Object?>(_locationKey)
      ?.tryGet<String>('uri');
  return GeoUri.tryParse(direct ?? nested);
}
