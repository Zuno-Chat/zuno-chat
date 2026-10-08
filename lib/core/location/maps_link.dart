import 'geo_uri.dart';

enum MapsApp { geoIntent, appleMaps }

Uri mapsLink(GeoUri geo, MapsApp app) {
  final point = geo.point;
  return switch (app) {
    MapsApp.geoIntent => Uri.parse('geo:$point?q=$point'),
    MapsApp.appleMaps => Uri.parse(
      'https://maps.apple.com/?ll=$point&q=$point',
    ),
  };
}
