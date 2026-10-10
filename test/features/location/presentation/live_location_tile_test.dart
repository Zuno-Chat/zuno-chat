import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/location/live_location_viewing.dart';
import 'package:zuno/features/location/presentation/live_location_tile.dart';
import 'package:zuno/features/location/presentation/location_map_view.dart';

import '../../../helpers/fake_device_keys.dart';
import '../../../helpers/fake_live_location.dart';

void main() {
  late LiveLocationHarness harness;
  late int opened;

  setUp(() {
    harness = LiveLocationHarness();
    opened = 0;
    setSelfSignedTestDevices(harness.client, '@alex:x', ['PHONE']);
    harness.member('@alex:x', 'Alex');
  });

  tearDown(() => harness.dispose());

  Future<void> pumpTile(WidgetTester tester, String userId) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 280,
              child: Consumer(
                builder: (context, ref, _) {
                  final share = ref
                      .watch(liveSharesProvider(harness.room.id))
                      .where((share) => share.userId == userId)
                      .firstOrNull;
                  if (share == null) return const SizedBox.shrink();
                  return LiveLocationTile(
                    room: harness.room,
                    share: share,
                    radius: 12,
                    muted: Colors.grey,
                    trailing: const Text('12:00'),
                    onOpen: () => opened++,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows a live share and how fresh it is', (tester) async {
    harness.shareFrom('@alex:x');
    harness.positionFrom('@alex:x', deviceId: 'PHONE');
    await tester.pump();

    await pumpTile(tester, '@alex:x');

    expect(find.text('Live location'), findsOneWidget);
    expect(find.byType(LocationMapView), findsOneWidget);
    expect(find.textContaining('updated just now'), findsOneWidget);
    expect(find.text('12:00'), findsOneWidget);
    expect(find.text('Stop sharing'), findsNothing);
    await tester.tap(find.byType(GestureDetector).first);
    expect(opened, 1);
  });

  testWidgets('shows no map until a first position', (tester) async {
    harness.shareFrom('@alex:x');

    await pumpTile(tester, '@alex:x');

    expect(find.byType(LocationMapView), findsNothing);
    expect(find.textContaining('waiting for location'), findsOneWidget);
  });

  testWidgets('offers Stop on this device\'s own share', (tester) async {
    await harness.startSharing();

    await pumpTile(tester, '@me:x');
    expect(find.textContaining('Until'), findsOneWidget);
    expect(find.textContaining('updated'), findsNothing);
    await tester.tap(find.text('Stop sharing'));
    await tester.pump();

    expect(harness.sharing.shares.value, isEmpty);
  });
}
