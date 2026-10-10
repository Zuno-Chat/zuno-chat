import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:zuno/features/location/presentation/map_parts.dart';

const _berlin = LatLng(52.52, 13.405);
const _potsdam = LatLng(52.39, 13.065);
const _munich = LatLng(48.137, 11.575);

LatLng _north(LatLng from, double degrees) =>
    LatLng(from.latitude + degrees, from.longitude);

MapCamera _camera(
  LatLng center, {
  double zoom = 16,
  Size size = const Size(400, 800),
}) => MapCamera(
  crs: const Epsg3857(),
  center: center,
  zoom: zoom,
  rotation: 0,
  nonRotatedSize: size,
);

void main() {
  group('neighbourhoodBounds', () {
    test('a union of neighbourhoods knows its own width', () {
      final union = neighbourhoodBounds([_berlin, _potsdam]);

      expect(union.longitudeWidth, closeTo(union.east - union.west, 1e-9));
      expect(
        union.longitudeCenter,
        closeTo((union.east + union.west) / 2, 1e-9),
      );
    });
  });

  group('grownNeighbourhood', () {
    test('starts as the neighbourhood of the first point', () {
      expect(grownNeighbourhood(null, _berlin), neighbourhoodBounds([_berlin]));
    });

    test('grows to take in a point that moved on', () {
      final reach = grownNeighbourhood(null, _berlin);

      final grown = grownNeighbourhood(reach, _potsdam);

      expect(grown.containsBounds(reach), isTrue);
      expect(grown.containsBounds(neighbourhoodBounds([_potsdam])), isTrue);
    });

    test('stays the same box while a point moves within it', () {
      final reach = grownNeighbourhood(
        grownNeighbourhood(null, _berlin),
        _north(_berlin, 0.02),
      );

      expect(
        identical(grownNeighbourhood(reach, _north(_berlin, 0.01)), reach),
        isTrue,
      );
    });
  });

  group('regionOf', () {
    test('spans every box it is given', () {
      final berlin = neighbourhoodBounds([_berlin]);
      final munich = neighbourhoodBounds([_munich]);

      final region = regionOf([berlin, munich]);

      expect(region.containsBounds(berlin), isTrue);
      expect(region.containsBounds(munich), isTrue);
    });
  });

  group('zoomToFit', () {
    const phone = Size(360, 560);

    test('a country fits much further out than a neighbourhood', () {
      final city = zoomToFit(neighbourhoodBounds([_berlin]), phone);
      final country = zoomToFit(
        regionOf([
          neighbourhoodBounds([_berlin]),
          neighbourhoodBounds([_munich]),
        ]),
        phone,
      );

      expect(city, greaterThan(10.5));
      expect(country, lessThan(8));
    });

    test('the fitted view holds the whole region', () {
      final region = regionOf([
        neighbourhoodBounds([_berlin]),
        neighbourhoodBounds([_munich]),
      ]);

      final zoom = zoomToFit(region, phone, padding: const EdgeInsets.all(8));

      expect(
        _camera(
          region.center,
          zoom: zoom,
          size: phone,
        ).visibleBounds.containsBounds(region),
        isTrue,
      );
    });

    test('a map not laid out yet keeps city level', () {
      expect(zoomToFit(neighbourhoodBounds([_munich]), Size.zero), 12);
    });
  });
}
