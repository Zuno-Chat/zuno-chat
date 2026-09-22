import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/security/device_safety.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/auth/presentation/device_warning_page.dart';

void main() {
  Future<void> pumpPage(
    WidgetTester tester, {
    required Set<DeviceRisk> risks,
    VoidCallback? onContinue,
    Size size = const Size(360, 640),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: zunoLightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: DeviceWarningPage(risks: risks, onContinue: onContinue ?? () {}),
      ),
    );
  }

  testWidgets('names an unlocked bootloader and nothing else', (tester) async {
    await pumpPage(tester, risks: {DeviceRisk.unlockedBootloader});

    expect(find.text('This device may not be safe'), findsOneWidget);
    expect(find.text('The bootloader is unlocked'), findsOneWidget);
    expect(find.text('This device is rooted'), findsNothing);
  });

  testWidgets('names root access and nothing else', (tester) async {
    await pumpPage(tester, risks: {DeviceRisk.rooted});

    expect(find.text('This device is rooted'), findsOneWidget);
    expect(find.text('The bootloader is unlocked'), findsNothing);
  });

  testWidgets('names both risks when both were found', (tester) async {
    await pumpPage(
      tester,
      risks: {DeviceRisk.unlockedBootloader, DeviceRisk.rooted},
    );

    expect(find.text('The bootloader is unlocked'), findsOneWidget);
    expect(find.text('This device is rooted'), findsOneWidget);
  });

  testWidgets('continue anyway hands control back', (tester) async {
    var continued = 0;
    await pumpPage(
      tester,
      risks: {DeviceRisk.rooted},
      onContinue: () => continued++,
    );

    await tester.tap(find.text('Continue anyway'));

    expect(continued, 1);
  });

  for (final (name, size, textScale) in [
    ('a small screen', const Size(360, 640), 1.0),
    ('double-size text', const Size(360, 640), 2.0),
    ('landscape', const Size(640, 360), 1.0),
  ]) {
    testWidgets('both risks fit on $name with the button in reach', (
      tester,
    ) async {
      await pumpPage(
        tester,
        risks: {DeviceRisk.unlockedBootloader, DeviceRisk.rooted},
        size: size,
        textScale: textScale,
      );

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Continue anyway'));
      await tester.pump();
      expect(find.text('Continue anyway').hitTestable(), findsOneWidget);
    });
  }
}
