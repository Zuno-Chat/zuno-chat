import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/security/security_emphasis.dart';

void main() {
  test(
    'securityStatusIcon picks the attention glyph only when it is needed',
    () {
      expect(securityStatusIcon(attention: true), attentionIcon);
      expect(securityStatusIcon(attention: false), settledIcon);
    },
  );

  Future<BuildContext> contextWith(WidgetTester tester, ThemeData theme) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: theme,
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ),
    );
    return captured;
  }

  testWidgets('an approved device is a darker green on a light theme', (
    tester,
  ) async {
    final context = await contextWith(tester, ThemeData.light());

    expect(deviceApprovedColor(context), const Color(0xFF2E7D32));
  });

  testWidgets('an approved device is a lighter green on a dark theme', (
    tester,
  ) async {
    final context = await contextWith(tester, ThemeData.dark());

    expect(deviceApprovedColor(context), const Color(0xFF81C784));
  });
}
