import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/location/geo_uri.dart';
import 'package:zuno/core/location/maps_link.dart';

void main() {
  const geo = GeoUri(latitude: 52.5163, longitude: 13.3777);

  test('a geo intent drops a pin in whichever maps app takes it', () {
    expect(
      mapsLink(geo, MapsApp.geoIntent).toString(),
      'geo:52.5163,13.3777?q=52.5163,13.3777',
    );
  });

  test('Apple Maps gets a link it opens on the pin', () {
    expect(
      mapsLink(geo, MapsApp.appleMaps).toString(),
      'https://maps.apple.com/?ll=52.5163,13.3777&q=52.5163,13.3777',
    );
  });

  test('both drop trailing zeros, never precision', () {
    const round = GeoUri(latitude: 52.5, longitude: -0.123456789);

    expect(
      mapsLink(round, MapsApp.appleMaps).toString(),
      'https://maps.apple.com/?ll=52.5,-0.123457&q=52.5,-0.123457',
    );
  });
}
