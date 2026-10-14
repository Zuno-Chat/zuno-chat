import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/l10n/l10n.dart';

class LayoutCase {
  const LayoutCase(
    this.name,
    this.size, {
    this.textScale = 1,
    this.rtl = false,
    this.locale,
  });

  final String name;
  final Size size;
  final double textScale;
  final bool rtl;
  final Locale? locale;
}

final layoutMatrix = [
  const LayoutCase('small phone', Size(360, 640)),
  const LayoutCase('smallest phone, 2x text', Size(320, 568), textScale: 2),
  const LayoutCase('landscape', Size(640, 360)),
  const LayoutCase('landscape, 1.3x text', Size(640, 360), textScale: 1.3),
  const LayoutCase('right to left', Size(360, 640), rtl: true),
  for (final locale in AppLocalizations.supportedLocales.skip(1))
    LayoutCase(
      '$locale, smallest phone, 1.3x text',
      const Size(320, 568),
      textScale: 1.3,
      locale: locale,
    ),
];

Future<void> expectSurvivesLayoutMatrix(
  WidgetTester tester,
  Widget Function() build, {
  ThemeData? theme,
  Future<void> Function(String caseName, AppLocalizations l10n)? afterEach,
}) async {
  addTearDown(tester.view.reset);
  for (final entry in layoutMatrix) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = entry.size;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 48);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: entry.locale,
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(entry.textScale)),
          child: Directionality(
            textDirection: entry.rtl ? TextDirection.rtl : TextDirection.ltr,
            child: child!,
          ),
        ),
        home: build(),
      ),
    );
    await tester.pump();
    final error = tester.takeException();
    expect(
      error,
      isNull,
      reason:
          '${entry.name}\n'
          '${error is FlutterError ? error.toStringDeep() : ''}',
    );
    await afterEach?.call(
      entry.name,
      lookupAppLocalizations(
        entry.locale ?? AppLocalizations.supportedLocales.first,
      ),
    );
  }
}
