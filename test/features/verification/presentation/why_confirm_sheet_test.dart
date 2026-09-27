import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/verification/presentation/why_confirm_sheet.dart';

import '../../../helpers/layout_matrix.dart';

void main() {
  Future<List<bool?>> open(
    WidgetTester tester, {
    String? unavailableReason,
  }) async {
    final answers = <bool?>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: zunoLightTheme,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => answers.add(
              await showWhyConfirmSheet(
                context,
                name: '@sam',
                unavailableReason: unavailableReason,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return answers;
  }

  testWidgets('explains why, naming the person', (tester) async {
    await open(tester);

    expect(find.text('Make sure it is really @sam'), findsOneWidget);
    expect(find.textContaining('write as @sam'), findsOneWidget);
    expect(find.textContaining('compare pictures on a call'), findsOneWidget);
    expect(find.text('Someone else?'), findsOneWidget);
  });

  testWidgets('Confirm answers yes', (tester) async {
    final answers = await open(tester);

    await tester.tap(find.text('Confirm it is really @sam'));
    await tester.pumpAndSettle();

    expect(answers, [true]);
  });

  testWidgets('Not now answers no', (tester) async {
    final answers = await open(tester);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(answers, [false]);
  });

  testWidgets('closing it any other way answers nothing', (tester) async {
    final answers = await open(tester);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(answers, [null]);
  });

  testWidgets('when confirming cannot start yet it says why instead of '
      'offering it', (tester) async {
    final answers = await open(
      tester,
      unavailableReason: 'You can confirm @sam once they join.',
    );

    expect(find.text('You can confirm @sam once they join.'), findsOneWidget);
    expect(find.text('Confirm it is really @sam'), findsNothing);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(answers, [false]);
  });

  testWidgets('the diagram is left out of what a screen reader announces', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await open(tester);

    expect(find.bySemanticsLabel('Someone else?'), findsNothing);
    expect(
      find.bySemanticsLabel('Make sure it is really @sam'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('fits every screen, text size and direction', (tester) async {
    await expectSurvivesLayoutMatrix(
      tester,
      () => const Scaffold(body: WhyConfirmSheet(name: '@samantha.rivera')),
      theme: zunoLightTheme,
    );
  });
}
