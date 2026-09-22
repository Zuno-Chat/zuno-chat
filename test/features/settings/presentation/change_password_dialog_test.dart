import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/settings/presentation/change_password_dialog.dart';

import '../../../helpers/real_fonts.dart';

void main() {
  Future<void> openDialog(
    WidgetTester tester, {
    Size size = const Size(360, 640),
    double keyboard = 0,
    double textScale = 1,
  }) async {
    await tester.runAsync(loadRealRoboto);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: zunoLightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => ChangePasswordDialog(
                  username: 'alice',
                  onSubmit: (current, next) async {},
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the fields keep a gap between them', (tester) async {
    await openDialog(tester);

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(4));
    for (var i = 0; i < 3; i++) {
      final gap =
          tester.getTopLeft(fields.at(i + 1)).dy -
          tester.getBottomLeft(fields.at(i)).dy;
      expect(gap, greaterThanOrEqualTo(8), reason: 'after field $i');
    }
  });

  testWidgets('Cancel and Change password share one row on a small phone', (
    tester,
  ) async {
    await openDialog(tester);

    final cancel = tester.getCenter(find.widgetWithText(TextButton, 'Cancel'));
    final change = tester.getCenter(
      find.widgetWithText(FilledButton, 'Change password'),
    );
    expect(cancel.dy, closeTo(change.dy, 0.5));
    expect(cancel.dx, lessThan(change.dx));
  });

  testWidgets('when the buttons cannot share a row, the action comes first', (
    tester,
  ) async {
    await openDialog(tester, size: const Size(360, 900), textScale: 2);

    final cancel = tester.getCenter(find.widgetWithText(TextButton, 'Cancel'));
    final change = tester.getCenter(
      find.widgetWithText(FilledButton, 'Change password'),
    );
    expect(change.dy, lessThan(cancel.dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('with the keyboard open nothing overflows and every field can '
      'be reached', (tester) async {
    await openDialog(tester, keyboard: 320);

    expect(tester.takeException(), isNull);
    await tester.ensureVisible(
      find.widgetWithText(TextField, 'Confirm new password'),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
