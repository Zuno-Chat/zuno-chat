import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/ui/edit_text_dialog.dart';

void main() {
  Future<Future<String?>> open(
    WidgetTester tester, {
    String initialValue = '',
    bool allowEmpty = true,
    String? Function(String)? validator,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: Text('Settings')),
      ),
    );
    final result = showEditTextDialog(
      tester.element(find.text('Settings')),
      title: 'Room name',
      initialValue: initialValue,
      allowEmpty: allowEmpty,
      validator: validator,
    );
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('saves the trimmed text', (tester) async {
    final result = await open(tester, initialValue: 'Old');
    await tester.enterText(find.byType(TextField), '  Book club  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(await result, 'Book club');
  });

  testWidgets('a validation error keeps the dialog open until fixed', (
    tester,
  ) async {
    final result = await open(
      tester,
      validator: (value) => value.length < 3 ? 'Too short' : null,
    );
    await tester.enterText(find.byType(TextField), 'ab');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Too short'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pump();
    expect(find.text('Too short'), findsNothing);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(await result, 'abc');
  });

  testWidgets('an empty value is ignored when it is not allowed, and Cancel '
      'saves nothing', (tester) async {
    final result = await open(tester, initialValue: 'Alice', allowEmpty: false);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await result, isNull);
  });
}
