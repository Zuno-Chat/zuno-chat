import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:zuno/core/location/geo_uri.dart';
import 'package:zuno/core/location/map_tiles_provider.dart';
import 'package:zuno/features/location/presentation/location_map_view.dart';

const _geo = GeoUri(latitude: 52.5163, longitude: 13.3777);

const _fullScreenSize = Size(800, 600);
const _previewSize = Size(240, 150);

Widget _host({required bool interactive}) => ProviderScope(
  overrides: [
    mapTilesProvider.overrideWithValue(
      MapTiles(
        base: Uri.parse('https://example.org/tiles'),
        httpClient: MockClient((_) async => http.Response('', 404)),
        cachingProvider: const DisabledMapCachingProvider(),
      ),
    ),
    mapTilesAvailableProvider.overrideWith((ref) async => true),
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

  testWidgets('the tile layer fetches nothing beyond the viewport', (
    tester,
  ) async {
    await tester.pumpWidget(_host(interactive: true));
    await tester.pump();

    expect(tester.widget<TileLayer>(find.byType(TileLayer)).panBuffer, 0);
  });
}
