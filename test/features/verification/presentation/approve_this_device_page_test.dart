import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/ui/step_hero.dart';
import 'package:zuno/features/verification/presentation/approve_this_device_page.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool showStartOver,
    Size size = const Size(360, 640),
    FakeViewPadding padding = const FakeViewPadding(top: 24, bottom: 48),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.padding = padding;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matrixClientProvider.overrideWithValue(
            buildTestClient(userId: '@me:example.org'),
          ),
        ],
        child: MaterialApp(
          home: ApproveThisDevicePage(showStartOver: showStartOver),
        ),
      ),
    );
    await tester.pump();
  }

  double top(WidgetTester tester, String label) =>
      tester.getRect(find.text(label)).top;

  testWidgets('fits a small phone with the ways forward in order, Not now '
      'last', (tester) async {
    await pump(tester, showStartOver: true);

    expect(tester.takeException(), isNull);
    expect(find.byType(StepHero), findsOneWidget);
    final order = [
      'Approve from another device',
      'Enter recovery code',
      'Lost the code? Start over',
      'Not now',
    ].map((label) => top(tester, label)).toList();
    expect(order, [...order]..sort());
    expect(
      tester.getRect(find.widgetWithText(TextButton, 'Not now')).bottom,
      lessThanOrEqualTo(640 - 48),
    );
  });

  testWidgets('the buttons sit right under the explanation, not at the '
      'bottom of a tall screen', (tester) async {
    await pump(tester, showStartOver: true, size: const Size(412, 915));

    expect(tester.takeException(), isNull);
    final explanationBottom = tester
        .getRect(
          find.text('Approve this device and your message history comes back.'),
        )
        .bottom;
    expect(
      top(tester, 'Approve from another device') - explanationBottom,
      lessThan(60),
    );
  });

  testWidgets('Start over is offered only where it was asked for', (
    tester,
  ) async {
    await pump(tester, showStartOver: false);

    expect(find.text('Lost the code? Start over'), findsNothing);
    expect(find.text('Enter recovery code'), findsOneWidget);
  });

  testWidgets('in landscape the explanation is still readable', (tester) async {
    await pump(
      tester,
      showStartOver: true,
      size: const Size(640, 360),
      padding: const FakeViewPadding(top: 24),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byType(Scrollable).first).height,
      greaterThan(200),
    );
  });
}
