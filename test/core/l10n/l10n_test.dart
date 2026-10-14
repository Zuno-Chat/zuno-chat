import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/l10n/l10n.dart';

void main() {
  test('a regional variant resolves to its language', () {
    expect(resolveAppLocale(const [Locale('en', 'GB')]), const Locale('en'));
  });

  test('an unsupported phone language falls back to English', () {
    expect(resolveAppLocale(const [Locale('xx')]), const Locale('en'));
  });

  test('an engine reporting no languages falls back to English', () {
    expect(resolveAppLocale(const []), const Locale('en'));
  });

  test('the first supported language in the phone list wins', () {
    expect(
      resolveAppLocale(const [Locale('xx'), Locale('en', 'US')]),
      const Locale('en'),
    );
  });

  test('English stays the first supported language whatever else lands', () {
    expect(AppLocalizations.supportedLocales.first, const Locale('en'));
    expect(
      File('l10n.yaml').readAsLinesSync(),
      contains('preferred-supported-locales: [en]'),
    );
  });

  test('englishLocalizations is English', () {
    expect(englishLocalizations.localeName, 'en');
  });

  test('deviceLocalizations never throws', () {
    expect(deviceLocalizations().commonCancel, 'Cancel');
  });

  testWidgets('context.l10n reads the app strings', (tester) async {
    late AppLocalizations l10n;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            l10n = context.l10n;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(l10n.commonCancel, 'Cancel');
  });
}
