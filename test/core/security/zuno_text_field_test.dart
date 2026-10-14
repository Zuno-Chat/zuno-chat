import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/security/zuno_text_field.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

  TextField field(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField));

  testWidgets('the keyboard may learn where the app allows it', (tester) async {
    await pump(
      tester,
      const KeyboardLearning(
        allowed: true,
        child: ZunoTextField(autofillHints: null),
      ),
    );

    expect(field(tester).enableIMEPersonalizedLearning, isTrue);
  });

  testWidgets('the keyboard stops learning once the app forbids it', (
    tester,
  ) async {
    await pump(
      tester,
      const KeyboardLearning(
        allowed: true,
        child: ZunoTextField(autofillHints: null),
      ),
    );
    await pump(
      tester,
      const KeyboardLearning(
        allowed: false,
        child: ZunoTextField(autofillHints: null),
      ),
    );

    expect(field(tester).enableIMEPersonalizedLearning, isFalse);
  });

  testWidgets('with no app-wide choice, the keyboard does not learn', (
    tester,
  ) async {
    await pump(tester, const ZunoTextField(autofillHints: null));

    expect(field(tester).enableIMEPersonalizedLearning, isFalse);
  });

  testWidgets('hands its autofill choice to the field', (tester) async {
    await pump(
      tester,
      const Column(
        children: [
          ZunoTextField(autofillHints: [AutofillHints.username]),
          ZunoTextField(autofillHints: null),
        ],
      ),
    );

    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(fields.map((f) => f.autofillHints), [
      [AutofillHints.username],
      null,
    ]);
  });
}
