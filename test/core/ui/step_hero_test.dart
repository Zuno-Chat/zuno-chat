import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/ui/step_hero.dart';
import 'package:zuno/core/ui/zuno_theme.dart';

import '../../helpers/contrast.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child, {ThemeData? theme}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: theme ?? zunoLightTheme,
          home: Scaffold(body: Center(child: child)),
        ),
      );

  testWidgets('an icon sits in a soft circle', (tester) async {
    await pump(tester, const StepHero(icon: Icons.vpn_key_outlined));

    expect(tester.getSize(find.byType(StepHero)), const Size(112, 112));
    final icon = tester.widget<Icon>(find.byIcon(Icons.vpn_key_outlined));
    expect(icon.size, 48);
  });

  for (final theme in [zunoLightTheme, zunoDarkTheme]) {
    testWidgets('the icon reads on the circle, ${theme.brightness.name}', (
      tester,
    ) async {
      await pump(
        tester,
        const StepHero(icon: Icons.vpn_key_outlined),
        theme: theme,
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.vpn_key_outlined));
      final circle = tester.widget<Material>(
        find.descendant(
          of: find.byType(StepHero),
          matching: find.byType(Material),
        ),
      );
      expect(contrastRatio(icon.color!, circle.color!), greaterThan(4.5));
    });
  }

  testWidgets('a compact hero leaves room for dense steps', (tester) async {
    await pump(
      tester,
      const StepHero(icon: Icons.vpn_key_outlined, compact: true),
    );

    expect(tester.getSize(find.byType(StepHero)), const Size(72, 72));
    expect(tester.widget<Icon>(find.byIcon(Icons.vpn_key_outlined)).size, 32);
  });

  testWidgets('art replaces the icon', (tester) async {
    await pump(
      tester,
      const StepHero(child: SizedBox(key: ValueKey('art'), width: 56)),
    );

    expect(find.byKey(const ValueKey('art')), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('a tappable hero is one ink target with a label', (tester) async {
    var taps = 0;
    await pump(
      tester,
      StepHero(
        icon: Icons.person_outline,
        onTap: () => taps++,
        semanticLabel: 'Add a photo',
      ),
    );

    await tester.tap(find.byType(StepHero));
    expect(taps, 1);
    expect(find.bySemanticsLabel('Add a photo'), findsOneWidget);
  });

  testWidgets('a hero that is only decoration adds nothing for a screen '
      'reader', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, const StepHero(icon: Icons.vpn_key_outlined));

    expect(
      find.descendant(
        of: find.byType(StepHero),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.button != null,
        ),
      ),
      findsNothing,
    );
    handle.dispose();
  });
}
