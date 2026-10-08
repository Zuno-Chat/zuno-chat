import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/location/live_location_protocol.dart';
import 'package:zuno/features/location/presentation/live_location_banner.dart';
import 'package:zuno/features/location/presentation/live_location_map_page.dart';

import '../../../helpers/fake_device_keys.dart';
import '../../../helpers/fake_live_location.dart';

void main() {
  late LiveLocationHarness harness;

  setUp(() {
    harness = LiveLocationHarness();
    setSelfSignedTestDevices(harness.client, '@alex:x', ['PHONE']);
    harness.member('@alex:x', 'Alex');
  });

  tearDown(() => harness.dispose());

  Future<void> pumpBanner(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp(
          home: Scaffold(
            body: Column(children: [LiveLocationBanner(room: harness.room)]),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  List<String> watches() => [
    for (final sent in harness.client.toDevice)
      if (sent.type == liveLocationWatchType) sent.devices.single,
  ];

  testWidgets('stays out of the way while nobody shares', (tester) async {
    await pumpBanner(tester);

    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('names who shares, watches them and opens the map', (
    tester,
  ) async {
    harness.shareFrom('@alex:x');

    await pumpBanner(tester);

    expect(find.text('Alex is sharing live location'), findsOneWidget);
    expect(find.text('Stop'), findsNothing);
    expect(watches(), ['@alex:x/PHONE']);

    await tester.tap(find.text('Alex is sharing live location'));
    await tester.pumpAndSettle();
    expect(find.byType(LiveLocationMapPage), findsOneWidget);
  });

  testWidgets('stops watching once the room closes', (tester) async {
    harness.shareFrom('@alex:x');
    await pumpBanner(tester);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    final last = harness.client.toDevice.last;
    expect(last.type, liveLocationWatchType);
    expect(parseLiveWatch(last.content)?.active, false);
  });

  testWidgets('offers Stop while this device shares', (tester) async {
    harness.shareFrom('@alex:x');
    await harness.startSharing();

    await pumpBanner(tester);
    expect(find.text('You and Alex are sharing live location'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await tester.pump();

    expect(harness.sharing.shares.value, isEmpty);
    expect(find.text('Alex is sharing live location'), findsOneWidget);
  });
}
