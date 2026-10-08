import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/location/live_location_protocol.dart';
import 'package:zuno/features/location/presentation/live_location_watch_scope.dart';

import '../../../helpers/fake_device_keys.dart';
import '../../../helpers/fake_live_location.dart';

void main() {
  late LiveLocationHarness harness;

  setUp(() {
    harness = LiveLocationHarness();
    setSelfSignedTestDevices(harness.client, '@alex:x', ['PHONE']);
    harness.member('@alex:x', 'Alex');
    harness.shareFrom('@alex:x');
  });

  tearDown(() => harness.dispose());

  List<bool> watches() => [
    for (final sent in harness.client.toDevice)
      if (sent.type == liveLocationWatchType)
        parseLiveWatch(sent.content)!.active,
  ];

  Future<void> pumpScope(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: MaterialApp(
          home: Builder(
            builder: (context) => LiveLocationWatchScope(
              roomId: harness.room.id,
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('Covering')),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('watches while its screen shows', (tester) async {
    await pumpScope(tester);

    expect(watches(), [true]);
  });

  testWidgets('stops watching while another screen covers it', (tester) async {
    await pumpScope(tester);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(watches(), [true, false]);
  });

  testWidgets('watches again once that screen closes', (tester) async {
    await pumpScope(tester);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.text('Covering'))).pop();
    await tester.pumpAndSettle();

    expect(watches(), [true, false, true]);
  });

  testWidgets('stops watching while Zuno is in the background', (tester) async {
    await pumpScope(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(watches(), [true, false]);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(watches(), [true, false, true]);
  });

  testWidgets('keeps watching through a brief interruption', (tester) async {
    await pumpScope(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    expect(watches(), [true]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('a rebuild keeps the one watch', (tester) async {
    await pumpScope(tester);

    await pumpScope(tester);

    expect(watches(), [true]);
  });
}
