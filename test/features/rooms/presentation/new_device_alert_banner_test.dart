import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/security/new_device_alert.dart';
import 'package:zuno/core/security/new_device_alert_provider.dart';
import 'package:zuno/features/rooms/presentation/new_device_alert_banner.dart';

class _FakeNotifier extends NewDeviceAlertNotifier {
  final List<NewDeviceAlert> initial;

  _FakeNotifier(this.initial);

  @override
  List<NewDeviceAlert> build() => initial;

  @override
  void dismiss(NewDeviceAlert alert) {
    state = state.where((a) => a != alert).toList();
  }
}

void main() {
  Future<void> pump(WidgetTester tester, List<NewDeviceAlert> alerts) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          newDeviceAlertProvider.overrideWith(() => _FakeNotifier(alerts)),
        ],
        child: const MaterialApp(
          home: Scaffold(body: NewDeviceAlertBanner()),
        ),
      ),
    );
  }

  testWidgets('nothing to alert about renders nothing', (tester) async {
    await pump(tester, const []);

    expect(find.byKey(const ValueKey('newDeviceAlertBanner')), findsNothing);
  });

  testWidgets('names the device that just signed in', (tester) async {
    await pump(tester, const [
      NewDeviceAlert(deviceId: 'BBB', displayName: 'Pixel 8a'),
    ]);

    expect(find.textContaining('Pixel 8a'), findsOneWidget);
    expect(find.text('New sign-in'), findsOneWidget);
  });

  testWidgets('several queued alerts say how many more', (tester) async {
    await pump(tester, const [
      NewDeviceAlert(deviceId: 'BBB'),
      NewDeviceAlert(deviceId: 'CCC'),
    ]);

    expect(find.textContaining('+1 more'), findsOneWidget);
  });

  testWidgets('dismissing drops only the shown alert', (tester) async {
    await pump(tester, const [
      NewDeviceAlert(deviceId: 'BBB', displayName: 'First'),
      NewDeviceAlert(deviceId: 'CCC', displayName: 'Second'),
    ]);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('newDeviceAlertBanner')), findsOneWidget);
    expect(find.textContaining('Second'), findsOneWidget);
    expect(find.textContaining('First'), findsNothing);
  });

  testWidgets('dismissing the last alert closes the banner', (tester) async {
    await pump(tester, const [NewDeviceAlert(deviceId: 'BBB')]);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('newDeviceAlertBanner')), findsNothing);
  });
}
