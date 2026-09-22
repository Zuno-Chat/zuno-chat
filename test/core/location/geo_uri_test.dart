import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/location/geo_uri.dart';

void main() {
  group('parsing', () {
    test('reads latitude, longitude and uncertainty', () {
      final geo = GeoUri.tryParse('geo:52.5163,13.3777;u=25')!;

      expect(geo.latitude, 52.5163);
      expect(geo.longitude, 13.3777);
      expect(geo.uncertaintyMeters, 25);
    });

    test('uncertainty is optional', () {
      final geo = GeoUri.tryParse('geo:52.5163,13.3777')!;

      expect(geo.uncertaintyMeters, isNull);
    });

    test('tolerates an altitude, a wgs84 crs and mixed-case scheme', () {
      final geo = GeoUri.tryParse('GEO:-33.8688,151.2093,12;crs=WGS84;u=5.5')!;

      expect(geo.latitude, -33.8688);
      expect(geo.longitude, 151.2093);
      expect(geo.uncertaintyMeters, 5.5);
    });

    test('drops an unusable uncertainty but keeps the coordinates', () {
      expect(GeoUri.tryParse('geo:1,2;u=abc')!.uncertaintyMeters, isNull);
      expect(GeoUri.tryParse('geo:1,2;u=-4')!.uncertaintyMeters, isNull);
    });

    test('malformed input degrades to null rather than throwing', () {
      const malformed = [
        null,
        '',
        'geo:',
        'geo:abc,1',
        'geo:1',
        'geo:91,0',
        'geo:0,181',
        'geo:NaN,0',
        'geo:1,2;crs=nad27',
        'https://example.org/geo:1,2',
      ];
      for (final input in malformed) {
        expect(GeoUri.tryParse(input), isNull, reason: '"$input"');
      }
    });
  });

  group('formatting', () {
    test('round-trips through the wire format', () {
      const geo = GeoUri(
        latitude: 52.5163,
        longitude: 13.3777,
        uncertaintyMeters: 25,
      );

      expect(geo.toUriString(), 'geo:52.5163,13.3777;u=25');
      expect(GeoUri.tryParse(geo.toUriString()), geo);
    });

    test('omits uncertainty when unknown and trims float noise', () {
      const geo = GeoUri(latitude: 1.0, longitude: -2.5);

      expect(geo.toUriString(), 'geo:1,-2.5');
    });

    test('labels coordinates to four decimals', () {
      const geo = GeoUri(latitude: 52.51631234, longitude: 13.3777);

      expect(geo.coordinatesLabel, '52.5163, 13.3777');
    });

    test('opens in an external maps app with a query pin', () {
      const geo = GeoUri(latitude: 52.5163, longitude: 13.3777);

      expect(
        geo.externalMapsUri.toString(),
        'geo:52.5163,13.3777?q=52.5163,13.3777',
      );
    });
  });
}
