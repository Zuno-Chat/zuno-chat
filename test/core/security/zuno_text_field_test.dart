import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/security/zuno_text_field.dart';

import '../../helpers/zuno_app.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) =>
      tester.pumpWidget(inZunoApp(child));

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

  testWidgets('a hint lines up with the field icon', (tester) async {
    await pump(
      tester,
      const ZunoTextField(
        autofillHints: null,
        decoration: InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: 'Search',
        ),
      ),
    );

    expect(
      tester.getCenter(find.text('Search')).dy,
      moreOrLessEquals(
        tester.getCenter(find.byIcon(Icons.search)).dy,
        epsilon: 0.5,
      ),
    );
  });

  testWidgets('a hint with no icon stays centred in its box', (tester) async {
    await pump(
      tester,
      const ZunoTextField(
        autofillHints: null,
        decoration: InputDecoration(prefixText: '@', hintText: 'username'),
      ),
    );

    expect(
      tester.getCenter(find.text('username')).dy,
      moreOrLessEquals(
        tester.getCenter(find.byType(InputDecorator)).dy,
        epsilon: 0.5,
      ),
    );
  });

  testWidgets('typed text stays below a label beside an icon', (tester) async {
    await pump(
      tester,
      ZunoTextField(
        autofillHints: null,
        controller: TextEditingController(text: 'secret'),
        decoration: const InputDecoration(
          labelText: 'Password',
          suffixIcon: Icon(Icons.visibility),
        ),
      ),
    );

    expect(
      tester.getRect(find.text('secret')).top,
      greaterThanOrEqualTo(tester.getRect(find.text('Password')).bottom),
    );
  });

  group('a field with only a hint', () {
    String nameOf(WidgetTester tester) =>
        tester.getSemantics(find.byType(EditableText)).label;

    Future<void> fill(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('says its hint once while empty and keeps it once filled', (
      tester,
    ) async {
      await pump(
        tester,
        ZunoTextField(
          autofillHints: null,
          controller: TextEditingController(),
          decoration: const InputDecoration(hintText: 'Display name'),
        ),
      );
      expect(nameOf(tester), 'Display name');

      await fill(tester, 'Alex');
      expect(nameOf(tester), 'Display name');
    });

    testWidgets('keeps its name once typed into without a controller', (
      tester,
    ) async {
      await pump(
        tester,
        const ZunoTextField(
          autofillHints: null,
          decoration: InputDecoration(hintText: 'Search'),
        ),
      );
      await fill(tester, 'bob');

      expect(nameOf(tester), 'Search');
    });
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
