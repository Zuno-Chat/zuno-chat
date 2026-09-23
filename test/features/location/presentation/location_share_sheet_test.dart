import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/location/current_position.dart';
import 'package:zuno/core/location/geo_uri.dart';
import 'package:zuno/core/location/map_tiles_provider.dart';
import 'package:zuno/features/location/presentation/location_share_sheet.dart';

const _geo = GeoUri(
  latitude: 52.5163,
  longitude: 13.3777,
  uncertaintyMeters: 25,
);

class _Opened {
  Future<GeoUri?>? result;
}

Future<_Opened> _open(
  WidgetTester tester,
  Future<LocationFix> Function() locate,
) async {
  final opened = _Opened();
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [mapTilesProvider.overrideWith((ref) async => null)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  opened.result = showLocationShareSheet(context, find: locate),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return opened;
}

void main() {
  testWidgets('shows the fix and hands it back on send', (tester) async {
    final opened = await _open(
      tester,
      () async => const LocationFound(geo: _geo, approximate: false),
    );

    expect(find.text('Send location'), findsOneWidget);
    expect(find.textContaining('about 25 m'), findsOneWidget);
    expect(find.textContaining('Approximate'), findsNothing);

    await tester.tap(find.text('Send location'));
    await tester.pumpAndSettle();

    expect(await opened.result, _geo);
  });

  testWidgets('labels a coarse-only fix as approximate', (tester) async {
    await _open(
      tester,
      () async => const LocationFound(geo: _geo, approximate: true),
    );

    expect(find.textContaining('Approximate location'), findsOneWidget);
    expect(find.text('Send location'), findsOneWidget);
  });

  testWidgets('explains when location services are off', (tester) async {
    final opened = await _open(
      tester,
      () async => const LocationFailed(LocationFailure.servicesOff),
    );

    expect(find.textContaining('Location is off'), findsOneWidget);
    expect(find.text('Open settings'), findsOneWidget);
    expect(find.text('Send location'), findsNothing);

    await tester.tapAt(const Offset(180, 100));
    await tester.pumpAndSettle();
    expect(await opened.result, isNull);
  });

  testWidgets('offers a retry after a refusal', (tester) async {
    var attempts = 0;
    await _open(tester, () async {
      attempts++;
      return attempts == 1
          ? const LocationFailed(LocationFailure.denied)
          : const LocationFound(geo: _geo, approximate: false);
    });

    expect(find.textContaining('Allow location access'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('Send location'), findsOneWidget);
  });
}
