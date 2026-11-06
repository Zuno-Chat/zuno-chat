import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/card_group.dart';
import 'package:zuno/core/ui/circle_icon.dart';
import 'package:zuno/core/ui/sheet.dart';
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

  testWidgets('a card group on a sheet sits one surface step above it', (
    tester,
  ) async {
    await tester.pumpWidget(
      inZunoApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showSheet<void>(
              context: context,
              builder: (_) => const CardGroup(children: [Text('x')]),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(CardGroup),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, zunoLightTheme.colorScheme.surfaceContainer);
  });

  testWidgets('a card group can carry a title', (tester) async {
    await tester.pumpWidget(
      inZunoApp(const CardGroup(title: '4 members', children: [Text('x')])),
    );
    final title = tester.widget<Text>(find.text('4 members'));
    expect(title.style!.fontWeight, FontWeight.w500);
  });

  group('a sliver card group', () {
    const corner = Radius.circular(ZunoRadius.large);

    Future<void> pumpCard(
      WidgetTester tester, {
      required List<String> rows,
      String? title = 'Okafor family',
      bool highlighted = false,
      VoidCallback? onTitleTap,
      VoidCallback? onTitleLongPress,
      void Function(int index)? onBuild,
    }) => tester.pumpWidget(
      inZunoApp(
        CustomScrollView(
          slivers: [
            SliverCardGroup(
              title: title,
              leading: const CircleIcon(Icons.groups_outlined),
              onTitleTap: onTitleTap,
              onTitleLongPress: onTitleLongPress,
              highlighted: highlighted,
              itemCount: rows.length,
              itemBuilder: (context, index) {
                onBuild?.call(index);
                return SizedBox(height: 72, child: Text(rows[index]));
              },
            ),
          ],
        ),
      ),
    );

    Finder segmentOf(String text) => find
        .ancestor(of: find.text(text), matching: find.byType(Material))
        .first;

    Material segment(WidgetTester tester, String text) =>
        tester.widget<Material>(segmentOf(text));

    testWidgets('is one card: heading and rows share the card color, and '
        'only its outer corners round', (tester) async {
      await pumpCard(tester, rows: ['General', 'Holiday 2027', 'Recipes']);

      final heading = segment(tester, 'Okafor family');
      expect(heading.color, zunoLightTheme.colorScheme.surfaceContainerLow);
      expect(heading.borderRadius, const BorderRadius.vertical(top: corner));
      expect(heading.clipBehavior, Clip.antiAlias);
      expect(segment(tester, 'General').borderRadius, BorderRadius.zero);
      expect(segment(tester, 'Holiday 2027').borderRadius, BorderRadius.zero);
      expect(
        segment(tester, 'Recipes').borderRadius,
        const BorderRadius.vertical(bottom: corner),
      );
      expect(
        segment(tester, 'Recipes').color,
        zunoLightTheme.colorScheme.surfaceContainerLow,
      );
    });

    testWidgets('sits in the same margins as a card group', (tester) async {
      await pumpCard(tester, rows: ['General']);

      final card = tester.getRect(segmentOf('Okafor family'));
      expect(card.left, 12);
      expect(card.top, 6);
      expect(card.right, 800 - 12);
    });

    testWidgets('with no rows, its heading rounds all round', (tester) async {
      await pumpCard(tester, rows: const []);

      expect(
        segment(tester, 'Okafor family').borderRadius,
        BorderRadius.circular(ZunoRadius.large),
      );
    });

    testWidgets('without a title, the first row rounds the top', (
      tester,
    ) async {
      await pumpCard(tester, title: null, rows: ['First', 'Last']);

      expect(
        segment(tester, 'First').borderRadius,
        const BorderRadius.vertical(top: corner),
      );
    });

    testWidgets('a highlighted card takes the highlight color', (tester) async {
      await pumpCard(tester, highlighted: true, rows: ['General']);

      expect(
        segment(tester, 'General').color,
        zunoLightTheme.colorScheme.secondaryContainer,
      );
    });

    testWidgets('a tappable heading shows a chevron and reports taps and '
        'long-presses', (tester) async {
      var taps = 0;
      var holds = 0;
      await pumpCard(
        tester,
        rows: ['General'],
        onTitleTap: () => taps++,
        onTitleLongPress: () => holds++,
      );

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      await tester.tap(find.text('Okafor family'));
      await tester.longPress(find.text('Okafor family'));
      expect((taps, holds), (1, 1));
    });

    testWidgets('a heading that does nothing shows no chevron', (tester) async {
      await pumpCard(tester, rows: ['General']);

      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('builds rows only as they scroll into view', (tester) async {
      final built = <int>{};
      await pumpCard(
        tester,
        rows: [for (var i = 0; i < 500; i++) 'Room $i'],
        onBuild: built.add,
      );

      expect(built, contains(0));
      expect(built.length, lessThan(30));
    });
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
