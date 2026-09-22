import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/security/recovery_code.dart';
import 'package:zuno/core/security/security_providers.dart';
import 'package:zuno/features/settings/presentation/recovery_code_screens.dart';

RecoveryWordlist _wordlist() => RecoveryWordlist.parse(
  File('assets/wordlist/recovery_words.txt').readAsStringSync(),
);

Future<void> _pump(WidgetTester tester, {Size? size}) async {
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        recoveryWordlistProvider.overrideWith((ref) async => _wordlist()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: RecoveryCodeCreateFlow(busy: false, onComplete: (_) {}),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpConfirmStepWithKeyboard(WidgetTester tester) async {
  await _pump(tester, size: const Size(360, 640));
  final toConfirm = find.widgetWithText(FilledButton, 'Continue');
  await tester.ensureVisible(toConfirm);
  await tester.pumpAndSettle();
  await tester.tap(toConfirm);
  await tester.pumpAndSettle();
  tester.view.viewInsets = const FakeViewPadding(bottom: 300);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Continue comes after the words and every way to save them', (
    tester,
  ) async {
    await _pump(tester, size: const Size(360, 640));

    expect(tester.takeException(), isNull);
    final button = find.widgetWithText(FilledButton, 'Continue');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(button).top,
      greaterThan(tester.getRect(find.text('Copy')).bottom),
    );
    expect(tester.getRect(button).width, 360 - 48);
  });

  testWidgets('checking the saved copy does not overflow above the keyboard', (
    tester,
  ) async {
    await _pumpConfirmStepWithKeyboard(tester);

    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.widgetWithText(FilledButton, 'Done')).bottom,
      lessThanOrEqualTo(640 - 300),
    );
  });

  testWidgets('a wrong word says so where it can be seen, above the keyboard', (
    tester,
  ) async {
    await _pumpConfirmStepWithKeyboard(tester);

    await tester.enterText(find.byType(TextField).first, 'notaword');
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final mismatch = find.text('That does not match. Check your saved copy.');
    final error = tester.getRect(mismatch);
    final done = tester.getRect(find.widgetWithText(FilledButton, 'Done'));
    expect(error.top, greaterThanOrEqualTo(0));
    expect(error.bottom, lessThanOrEqualTo(done.top));
    expect(done.bottom, lessThanOrEqualTo(640 - 300));
    expect(
      find.ancestor(of: mismatch, matching: find.byType(Scrollable)),
      findsNothing,
    );
  });

  testWidgets('reveals exactly as many words as a code has', (tester) async {
    await _pump(tester, size: const Size(1080, 2400));

    final wordlist = _wordlist();
    final shown = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((w) => w.data)
        .whereType<String>()
        .toList();

    expect(shown, hasLength(recoveryCodeWordCount));
    for (final word in shown) {
      expect(wordlist.contains(word), isTrue, reason: word);
    }
  });

  testWidgets('numbers every word, so the confirm step can ask by position', (
    tester,
  ) async {
    await _pump(tester, size: const Size(1080, 2400));
    for (var i = 1; i <= recoveryCodeWordCount; i++) {
      expect(find.text('$i'), findsOneWidget, reason: 'position $i');
    }
  });

  testWidgets('lays the words out without overflowing a phone screen', (
    tester,
  ) async {
    await _pump(tester, size: const Size(1080, 2400));
    expect(tester.takeException(), isNull);
  });

  testWidgets('falls back to one column on a narrow screen', (tester) async {
    await _pump(tester, size: const Size(320, 1400));
    expect(tester.takeException(), isNull);
    expect(
      tester.widgetList<SelectableText>(find.byType(SelectableText)),
      hasLength(recoveryCodeWordCount),
    );
  });

  testWidgets('asks for two words by position before finishing', (
    tester,
  ) async {
    await _pump(tester, size: const Size(1080, 2400));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Check your saved copy'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Show the code again'), findsOneWidget);
  });

  testWidgets('a wrong answer offers the code again instead of failing', (
    tester,
  ) async {
    await _pump(tester, size: const Size(1080, 2400));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'definitelywrong');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.textContaining('does not match'), findsOneWidget);
    expect(find.text('Show the code again'), findsOneWidget);
  });
}
