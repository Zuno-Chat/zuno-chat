import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/card_group.dart';
import 'package:zuno/core/ui/circle_icon.dart';
import 'package:zuno/core/ui/zuno_theme.dart';

import '../../helpers/zuno_app.dart';

void main() {
  testWidgets('a card group is an ink surface with the large radius', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      inZunoApp(
        CardGroup(
          children: [ListTile(title: const Text('Row'), onTap: () => taps++)],
        ),
      ),
    );
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(CardGroup),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, zunoLightTheme.colorScheme.surfaceContainerLow);
    expect(material.borderRadius, BorderRadius.circular(ZunoRadius.large));
    expect(material.clipBehavior, Clip.antiAlias);

    await tester.tap(find.text('Row'));
    expect(taps, 1);
  });

  testWidgets('a card group can carry a title', (tester) async {
    await tester.pumpWidget(
      inZunoApp(const CardGroup(title: '4 members', children: [Text('x')])),
    );
    final title = tester.widget<Text>(find.text('4 members'));
    expect(title.style!.fontWeight, FontWeight.w500);
  });

  testWidgets('a circle icon is 40 px; danger turns the glyph red', (
    tester,
  ) async {
    await tester.pumpWidget(inZunoApp(const CircleIcon(Icons.shield_outlined)));
    expect(tester.getSize(find.byType(CircleIcon)), const Size(40, 40));
    expect(
      tester.widget<Icon>(find.byType(Icon)).color,
      zunoLightTheme.colorScheme.onSurface,
    );

    await tester.pumpWidget(
      inZunoApp(const CircleIcon(Icons.logout_outlined, danger: true)),
    );
    expect(
      tester.widget<Icon>(find.byType(Icon)).color,
      zunoLightTheme.colorScheme.error,
    );
  });
}
