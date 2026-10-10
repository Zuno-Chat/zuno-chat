import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/features/location/presentation/own_live_location_banner.dart';

import '../../../helpers/fake_live_location.dart';

void main() {
  late LiveLocationHarness harness;
  late List<Room> opened;

  setUp(() {
    harness = LiveLocationHarness();
    opened = [];
  });

  tearDown(() => harness.dispose());

  Future<void> pumpBanner(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp(
          home: Scaffold(
            body: Column(children: [OwnLiveLocationBanner(onOpen: opened.add)]),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows only while this device shares, says where, and stops it '
      'all', (tester) async {
    await pumpBanner(tester);
    expect(find.text('Sharing live location'), findsNothing);

    await harness.startSharing();
    await tester.pump();

    expect(find.text('Sharing live location'), findsOneWidget);
    expect(find.text('In Family'), findsOneWidget);

    await tester.tap(find.text('In Family'));
    expect(opened.single.id, '!family:x');

    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(harness.sharing.shares.value, isEmpty);
    expect(find.text('Sharing live location'), findsNothing);
  });
}
