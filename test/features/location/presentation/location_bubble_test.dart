import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:zuno/core/location/geo_uri.dart';
import 'package:zuno/core/location/map_tiles_provider.dart';
import 'package:zuno/features/location/presentation/location_bubble.dart';

const _geo = GeoUri(
  latitude: 52.5163,
  longitude: 13.3777,
  uncertaintyMeters: 25,
);

Widget _host(Widget child, {MapTiles? tiles}) => ProviderScope(
  overrides: [
    mapTilesProvider.overrideWithValue(tiles),
    mapTilesAvailableProvider.overrideWith((ref) async => tiles != null),
  ],
  child: MaterialApp(
    home: Scaffold(body: SizedBox(width: 240, child: child)),
  ),
);

MapTiles _offlineTiles() => MapTiles(
  base: Uri.parse('https://example.org/tiles'),
  httpClient: MockClient((_) async => http.Response('', 404)),
  cachingProvider: const DisabledMapCachingProvider(),
);

void main() {
  testWidgets('without a tile proxy the pin shows coordinates, not a map', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        LocationBubble(
          geo: _geo,
          radius: 5,
          trailing: const Text('14:02'),
          onOpen: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('52.5163, 13.3777'), findsOneWidget);
    expect(find.byType(FlutterMap), findsNothing);
    expect(find.text('14:02'), findsOneWidget);
  });

  testWidgets('tapping the preview opens the pin', (tester) async {
    GeoUri? opened;
    await tester.pumpWidget(
      _host(
        LocationBubble(
          geo: _geo,
          radius: 5,
          trailing: const SizedBox.shrink(),
          onOpen: (geo) => opened = geo,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.location_on));
    expect(opened, _geo);
  });

  testWidgets('tapping a loaded map opens the pin too', (tester) async {
    GeoUri? opened;
    await tester.pumpWidget(
      _host(
        LocationBubble(
          geo: _geo,
          radius: 5,
          trailing: const SizedBox.shrink(),
          onOpen: (geo) => opened = geo,
        ),
        tiles: _offlineTiles(),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(FlutterMap), findsOneWidget);
    await tester.tap(find.byType(FlutterMap), warnIfMissed: false);
    expect(opened, _geo);
  });

  testWidgets('a pin with unusable coordinates is still a labelled bubble', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      _host(
        LocationBubble(
          geo: null,
          radius: 5,
          trailing: const Text('14:02'),
          onOpen: (_) => opened = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Location'), findsOneWidget);
    expect(find.byIcon(Icons.location_on), findsNothing);
    expect(find.text('14:02'), findsOneWidget);
    await tester.tap(find.text('Location'));
    expect(opened, isFalse);
  });
}
