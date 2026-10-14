import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/l10n/app_locale.dart';
import 'package:zuno/core/l10n/l10n.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> reads;
  late Object? Function() reply;

  setUp(() {
    reads = [];
    reply = () => 'en';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(localeChannel, (call) async {
          reads.add(call.method);
          return reply();
        });
  });

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(localeChannel, null),
  );

  group('AppLocale', () {
    test('the language the platform picked is the app language', () async {
      reply = () => 'el';

      await AppLocale.instance.start();

      expect(reads, ['resolved']);
      expect(AppLocale.instance.value, const Locale('el'));
      expect(deviceLocalizations().localeName, 'el');
    });

    testWidgets('a failed read falls back to Flutter resolving the phone '
        'languages', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('el', 'GR')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      reply = () => throw PlatformException(code: 'boom');

      await tester.runAsync(AppLocale.instance.start);

      expect(AppLocale.instance.value, const Locale('el'));
    });

    test('a regional answer maps to its own file', () async {
      reply = () => 'pt_PT';

      await AppLocale.instance.start();

      expect(AppLocale.instance.value, const Locale('pt', 'PT'));
      expect(deviceLocalizations().localeName, 'pt_PT');
    });

    testWidgets('a failed read gives a Portuguese phone its own region', (
      tester,
    ) async {
      tester.platformDispatcher.localesTestValue = const [Locale('pt', 'PT')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      reply = () => throw PlatformException(code: 'boom');

      await tester.runAsync(AppLocale.instance.start);

      expect(AppLocale.instance.value, const Locale('pt', 'PT'));
    });

    test('a language Zuno does not ship falls back to English', () async {
      reply = () => 'xx';

      await AppLocale.instance.start();

      expect(AppLocale.instance.value, const Locale('en'));
    });

    testWidgets('a phone language change asks the platform again and tells '
        'listeners', (tester) async {
      await tester.runAsync(AppLocale.instance.start);
      var changes = 0;
      void count() => changes++;
      AppLocale.instance.addListener(count);
      addTearDown(() => AppLocale.instance.removeListener(count));
      reply = () => 'el';

      tester.platformDispatcher.localesTestValue = const [Locale('el')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pump();

      expect(reads, ['resolved', 'resolved']);
      expect(AppLocale.instance.value, const Locale('el'));
      expect(changes, 1);
    });

    testWidgets('the same answer after a change tells no one', (tester) async {
      await tester.runAsync(AppLocale.instance.start);
      var changes = 0;
      void count() => changes++;
      AppLocale.instance.addListener(count);
      addTearDown(() => AppLocale.instance.removeListener(count));

      tester.platformDispatcher.localesTestValue = const [Locale('en', 'GB')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pump();

      expect(reads, ['resolved', 'resolved']);
      expect(changes, 0);
    });

    test('until asked, it is English in an English test run', () {
      expect(AppLocale.instance.value, const Locale('en'));
      expect(deviceLocalizations().commonCancel, 'Cancel');
    });
  });

  test('English stays the first supported language whatever else lands', () {
    expect(AppLocalizations.supportedLocales.first, const Locale('en'));
    expect(
      File('l10n.yaml').readAsLinesSync(),
      contains('preferred-supported-locales: [en]'),
    );
  });

  test('each translation names itself and counts zero by its own rule', () {
    for (final (locale, name, zero) in const [
      (Locale('el'), 'Ελληνικά', '0 μέλη'),
      (Locale('pt'), 'Português (Brasil)', '0 membro'),
      (Locale('pt', 'PT'), 'Português (Portugal)', '0 membros'),
      (Locale('fr'), 'Français', '0 membre'),
      (Locale('es'), 'Español', '0 miembros'),
      (Locale('it'), 'Italiano', '0 membri'),
    ]) {
      final l10n = lookupAppLocalizations(locale);
      expect(l10n.languageNativeName, name, reason: '$locale');
      expect(l10n.unitsMembers(0), zero, reason: '$locale');
    }
  });

  test('englishLocalizations is English', () {
    expect(englishLocalizations.localeName, 'en');
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
