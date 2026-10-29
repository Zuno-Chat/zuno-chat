import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/ui/confirm_dialog.dart';

void main() {
  Future<BuildContext> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: Text('Chat')),
      ),
    );
    return tester.element(find.text('Chat'));
  }

  Future<bool> ask(
    WidgetTester tester, {
    ConfirmTone tone = ConfirmTone.plain,
    String? cancelLabel,
    required Future<void> Function() answer,
  }) async {
    final context = await pumpHost(tester);
    final result = confirm(
      context,
      title: 'Delete message?',
      body: 'It goes for everyone.',
      confirmLabel: 'Delete',
      cancelLabel: cancelLabel,
      tone: tone,
    );
    await tester.pumpAndSettle();
    await answer();
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('says yes when the action is tapped', (tester) async {
    expect(
      await ask(tester, answer: () => tester.tap(find.text('Delete'))),
      isTrue,
    );
  });

  testWidgets('says no on Cancel and when dismissed outside', (tester) async {
    expect(
      await ask(tester, answer: () => tester.tap(find.text('Cancel'))),
      isFalse,
    );
    expect(
      await ask(tester, answer: () => tester.tapAt(const Offset(5, 5))),
      isFalse,
    );
  });

  testWidgets('a destructive action is red, a plain one is not', (
    tester,
  ) async {
    Color? actionColor() => tester
        .widget<DefaultTextStyle>(
          find
              .ancestor(
                of: find.text('Delete'),
                matching: find.byType(DefaultTextStyle),
              )
              .first,
        )
        .style
        .color;

    final context = await pumpHost(tester);
    final error = Theme.of(context).colorScheme.error;

    unawaited(
      confirm(
        context,
        title: 'Delete message?',
        confirmLabel: 'Delete',
        tone: ConfirmTone.destructive,
      ),
    );
    await tester.pumpAndSettle();
    expect(actionColor(), error);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    unawaited(confirm(context, title: 'Leave?', confirmLabel: 'Delete'));
    await tester.pumpAndSettle();
    expect(actionColor(), isNot(error));
  });

  testWidgets('a primary action is a filled button with its own cancel '
      'label', (tester) async {
    final context = await pumpHost(tester);
    unawaited(
      confirm(
        context,
        title: 'Set up recovery?',
        confirmLabel: 'Continue',
        cancelLabel: 'Not now',
        tone: ConfirmTone.primary,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
  });
}
