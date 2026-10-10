import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:zuno/core/location/geo_uri.dart';
import 'package:zuno/core/location/map_tiles.dart';
import 'package:zuno/core/location/map_tiles_provider.dart';
import 'package:zuno/features/location/presentation/location_map_view.dart';

const _geo = GeoUri(latitude: 52.5163, longitude: 13.3777);

const _fullScreenSize = Size(800, 600);
const _previewSize = Size(240, 150);
const _credit = 'MapTiler OpenStreetMap contributors';
const _agent = 'Zuno/1.2.0 (Android; im.zuno.chat)';

Widget _host({
  required bool interactive,
  String? attribution = _credit,
  GeoUri geo = _geo,
  bool persistTiles = true,
}) => ProviderScope(
  overrides: [
    mapTilesProvider.overrideWith(
      (ref) async => MapTiles(
        source: TileSource(
          urlTemplate: 'https://tiles.example.org/{z}/{x}/{y}.png',
          attribution: attribution,
        ),
        httpClient: MockClient((_) async => http.Response('', 404)),
        userAgent: _agent,
        cachingProvider: const DisabledMapCachingProvider(),
      ),
    ),
  ],
  child: MaterialApp(
    home: Scaffold(
      body: SizedBox.fromSize(
        size: interactive ? _fullScreenSize : _previewSize,
        child: LocationMapView(
          geo: geo,
          interactive: interactive,
          persistTiles: persistTiles,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('a preview map carries no attribution bar', (tester) async {
    await tester.pumpWidget(_host(interactive: false));
    await tester.pump();

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byType(SimpleAttributionWidget), findsNothing);
  });

  testWidgets('the full map credits whoever the server names, tucked '
      'top-right', (tester) async {
    await tester.pumpWidget(_host(interactive: true));
    await tester.pump();

    final attribution = tester.widget<SimpleAttributionWidget>(
      find.byType(SimpleAttributionWidget),
    );
    expect(attribution.alignment, Alignment.topRight);
    expect(find.text(_credit), findsOneWidget);
  });

  testWidgets('an uncredited source shows no attribution bar', (tester) async {
    await tester.pumpWidget(_host(interactive: true, attribution: null));
    await tester.pump();

    expect(find.byType(SimpleAttributionWidget), findsNothing);
  });

  testWidgets('the tile layer fetches nothing beyond the viewport', (
    tester,
  ) async {
    await tester.pumpWidget(_host(interactive: true));
    await tester.pump();

    expect(tester.widget<TileLayer>(find.byType(TileLayer)).panBuffer, 0);
  });

  testWidgets('a live view keeps its tiles off the disk', (tester) async {
    await tester.pumpWidget(_host(interactive: false, persistTiles: false));
    await tester.pump();

    final layer = tester.widget<TileLayer>(find.byType(TileLayer));
    final provider = layer.tileProvider as NetworkTileProvider;
    expect(provider.cachingProvider, isA<DisabledMapCachingProvider>());
  });

  testWidgets('tiles are fetched as Zuno, not as flutter_map', (tester) async {
    await tester.pumpWidget(_host(interactive: true));
    await tester.pump();

    final layer = tester.widget<TileLayer>(find.byType(TileLayer));
    expect(layer.tileProvider.headers['User-Agent'], _agent);
  });

  group('full map limits', () {
    MapOptions optionsOf(WidgetTester tester) =>
        tester.widget<FlutterMap>(find.byType(FlutterMap)).options;

    testWidgets('stops zooming out at city level', (tester) async {
      await tester.pumpWidget(_host(interactive: true));
      await tester.pump();

      expect(optionsOf(tester).minZoom, 12);
    });

    testWidgets('pans no further than 10 km from the pin', (tester) async {
      await tester.pumpWidget(_host(interactive: true));
      await tester.pump();

      final constraint = optionsOf(tester).cameraConstraint;
      expect(constraint, isA<ContainCamera>());
      final bounds = (constraint as ContainCamera).bounds;
      final pin = LatLng(_geo.latitude, _geo.longitude);
      const distance = Distance();
      expect(bounds.contains(pin), isTrue);
      expect(
        distance.as(
          LengthUnit.Kilometer,
          LatLng(bounds.south, pin.longitude),
          LatLng(bounds.north, pin.longitude),
        ),
        closeTo(20, 0.5),
      );
      expect(
        distance.as(
          LengthUnit.Kilometer,
          LatLng(pin.latitude, bounds.west),
          LatLng(pin.latitude, bounds.east),
        ),
        closeTo(20, 0.5),
      );
    });

    testWidgets('a pin near the pole still opens', (tester) async {
      await tester.pumpWidget(
        _host(
          interactive: true,
          geo: const GeoUri(latitude: 89.99, longitude: 179.99),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(FlutterMap), findsOneWidget);
    });

    testWidgets('a preview carries no limits of its own', (tester) async {
      await tester.pumpWidget(_host(interactive: false));
      await tester.pump();

      expect(optionsOf(tester).minZoom, isNull);
      expect(optionsOf(tester).cameraConstraint, isA<UnconstrainedCamera>());
    });
  });

  group('a moving pin', () {
    const moved = GeoUri(latitude: 52.5603, longitude: 13.3777);

    MapCamera cameraOf(WidgetTester tester) => tester
        .widget<FlutterMap>(find.byType(FlutterMap))
        .mapController!
        .camera;

    double metersFrom(WidgetTester tester, GeoUri geo) => const Distance().as(
      LengthUnit.Meter,
      cameraOf(tester).center,
      LatLng(geo.latitude, geo.longitude),
    );

    testWidgets('a preview follows the pin', (tester) async {
      await tester.pumpWidget(_host(interactive: false));
      await tester.pump();

      await tester.pumpWidget(_host(interactive: false, geo: moved));
      await tester.pump();

      expect(metersFrom(tester, moved), lessThan(1));
    });

    testWidgets('a full map follows the pin past its first neighbourhood', (
      tester,
    ) async {
      await tester.pumpWidget(_host(interactive: true));
      await tester.pump();

      await tester.pumpWidget(_host(interactive: true, geo: moved));
      await tester.pump();

      expect(metersFrom(tester, moved), lessThan(1));
      final bounds =
          (tester
                      .widget<FlutterMap>(find.byType(FlutterMap))
                      .options
                      .cameraConstraint
                  as ContainCamera)
              .bounds;
      expect(bounds.contains(LatLng(_geo.latitude, _geo.longitude)), isTrue);
      expect(bounds.contains(LatLng(moved.latitude, moved.longitude)), isTrue);
    });

    testWidgets('a pin that stays put leaves the camera where it is', (
      tester,
    ) async {
      await tester.pumpWidget(_host(interactive: true));
      await tester.pump();
      await tester.drag(find.byType(FlutterMap), const Offset(0, 120));
      await tester.pump(const Duration(seconds: 1));
      final dragged = cameraOf(tester).center;

      await tester.pumpWidget(_host(interactive: true));
      await tester.pump();

      expect(cameraOf(tester).center, dragged);
    });
  });
}
