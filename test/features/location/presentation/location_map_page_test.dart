import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/location/geo_uri.dart';
import 'package:zuno/core/location/map_tiles_provider.dart';
import 'package:zuno/features/location/presentation/location_map_page.dart';
import 'package:zuno/features/location/presentation/location_map_view.dart';

const _geo = GeoUri(
  latitude: 52.5163,
  longitude: 13.3777,
  uncertaintyMeters: 12.4,
);

void main() {
  late List<Map<Object?, Object?>> launched;
  late Future<Object?> Function() answer;

  setUp(() {
    launched = [];
    answer = () async => true;
  });

  void mockLauncher(WidgetTester tester) {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'launch') return null;
      launched.add(call.arguments as Map<Object?, Object?>);
      return answer();
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }

  Future<void> pumpPage(WidgetTester tester, {GeoUri geo = _geo}) async {
    mockLauncher(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mapTilesProvider.overrideWith((ref) async => null)],
        child: MaterialApp(
          home: LocationMapPage(
            geo: geo,
            senderName: 'Ann',
            sentAt: DateTime(2026, 9, 14, 18, 5),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('accuracyLabel', () {
    test('is empty without an accuracy', () {
      expect(accuracyLabel(null), isNull);
    });

    test('rounds to whole metres below a kilometre', () {
      expect(accuracyLabel(12.4), 'about 12 m');
      expect(accuracyLabel(999.4), 'about 999 m');
    });

    test('switches to kilometres once it rounds to one', () {
      expect(accuracyLabel(999.6), 'about 1.0 km');
      expect(accuracyLabel(1500), 'about 1.5 km');
    });
  });

  testWidgets('names the sender and shows where and when', (tester) async {
    await pumpPage(tester);

    expect(find.widgetWithText(AppBar, 'Ann'), findsOneWidget);
    expect(find.text('52.5163, 13.3777'), findsOneWidget);
    expect(find.text('about 12 m · Mon, Sep 14 · 6:05 PM'), findsOneWidget);
    final map = tester.widget<LocationMapView>(find.byType(LocationMapView));
    expect(map.interactive, isTrue);
    expect(map.zoom, 16);
  });

  testWidgets('leaves the accuracy out when there is none', (tester) async {
    await pumpPage(
      tester,
      geo: const GeoUri(latitude: 52.5163, longitude: 13.3777),
    );

    expect(find.text('Mon, Sep 14 · 6:05 PM'), findsOneWidget);
  });

  testWidgets('the button hands the pin to a maps app', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Open in maps app'));
    await tester.pump();

    expect(launched.single['url'], 'geo:52.5163,13.3777?q=52.5163,13.3777');
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('the app bar action does the same', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byTooltip('Open in maps app'));
    await tester.pump();

    expect(launched, hasLength(1));
  });

  testWidgets('says so when no maps app takes it', (tester) async {
    answer = () async => false;
    await pumpPage(tester);

    await tester.tap(find.byTooltip('Open in maps app'));
    await tester.pump();

    expect(find.text('No maps app found'), findsOneWidget);
  });

  testWidgets('says so when opening one fails', (tester) async {
    answer = () async => throw PlatformException(code: 'ACTIVITY_NOT_FOUND');
    await pumpPage(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Open in maps app'));
    await tester.pump();

    expect(find.text('No maps app found'), findsOneWidget);
  });
}
