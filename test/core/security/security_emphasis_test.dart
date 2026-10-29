import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/security/security_emphasis.dart';
import 'package:zuno/core/ui/zuno_colors.dart';
import 'package:zuno/core/ui/zuno_theme.dart';

void main() {
  test(
    'securityStatusIcon picks the attention glyph only when it is needed',
    () {
      expect(securityStatusIcon(attention: true), attentionIcon);
      expect(securityStatusIcon(attention: false), settledIcon);
    },
  );

  Future<BuildContext> contextWith(
    WidgetTester tester,
    ThemeData theme, {
    Widget child = const SizedBox(),
  }) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: theme,
        home: Builder(
          builder: (context) {
            captured = context;
            return Center(child: child);
          },
        ),
      ),
    );
    return captured;
  }

  testWidgets('an approved device wears the theme\'s success green on a '
      'light theme', (tester) async {
    final context = await contextWith(tester, zunoLightTheme);

    expect(deviceApprovedColor(context), ZunoColors.light.success);
  });

  testWidgets('an approved device wears the theme\'s success green on a dark '
      'theme', (tester) async {
    final context = await contextWith(tester, zunoDarkTheme);

    expect(deviceApprovedColor(context), ZunoColors.dark.success);
  });

  group('the not-encrypted mark', () {
    testWidgets('is the red open lock, at the size asked for', (tester) async {
      final context = await contextWith(
        tester,
        zunoLightTheme,
        child: const NotEncryptedMark(size: 14),
      );

      final icon = tester.widget<Icon>(find.byIcon(notEncryptedIcon));
      expect(icon.size, 14);
      expect(icon.color, notEncryptedColor(context));
    });

    testWidgets('tells a screen reader the chat is not encrypted', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await contextWith(
        tester,
        zunoLightTheme,
        child: const NotEncryptedMark(),
      );

      expect(find.bySemanticsLabel('Not encrypted'), findsOneWidget);
      semantics.dispose();
    });
  });
}
