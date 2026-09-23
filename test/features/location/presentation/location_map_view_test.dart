import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:zuno/core/location/geo_uri.dart';
import 'package:zuno/core/location/map_tiles.dart';
import 'package:zuno/core/location/map_tiles_provider.dart';
import 'package:zuno/features/location/presentation/location_map_view.dart';

const _geo = GeoUri(latitude: 52.5163, longitude: 13.3777);

const _fullScreenSize = Size(800, 600);
const _previewSize = Size(240, 150);
const _credit = 'MapTiler OpenStreetMap contributors';

Widget _host({required bool interactive, String? attribution = _credit}) =>
    ProviderScope(
      overrides: [
        mapTilesProvider.overrideWith(
          (ref) async => MapTiles(
            source: TileSource(
              urlTemplate: 'https://tiles.example.org/{z}/{x}/{y}.png',
              attribution: attribution,
            ),
            httpClient: MockClient((_) async => http.Response('', 404)),
            cachingProvider: const DisabledMapCachingProvider(),
          ),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox.fromSize(
            size: interactive ? _fullScreenSize : _previewSize,
            child: LocationMapView(geo: _geo, interactive: interactive),
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

  testWidgets('the full map keeps the attribution, tucked top-right', (
    tester,
  ) async {
    await tester.pumpWidget(_host(interactive: true));
    await tester.pump();

    final attribution = tester.widget<SimpleAttributionWidget>(
      find.byType(SimpleAttributionWidget),
    );
    expect(attribution.alignment, Alignment.topRight);
  });

  testWidgets('the full map credits whoever the server names', (tester) async {
    await tester.pumpWidget(_host(interactive: true));
    await tester.pump();

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
}
