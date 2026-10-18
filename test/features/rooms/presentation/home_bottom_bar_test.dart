import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/ui/keep_clear.dart';
import 'package:zuno/core/ui/zuno_motion.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/rooms/presentation/home_bottom_bar.dart';

import '../../../helpers/layout_matrix.dart';

void main() {
  Widget bar({
    HomeTab selected = HomeTab.chats,
    bool chatsUnread = false,
    bool communitiesUnread = false,
    ValueChanged<HomeTab>? onSelect,
    VoidCallback? onNew,
  }) => Scaffold(
    bottomNavigationBar: HomeBottomBar(
      selected: selected,
      chatsUnread: chatsUnread,
      communitiesUnread: communitiesUnread,
      onSelect: onSelect ?? (_) {},
      onNew: onNew ?? () {},
    ),
  );

  Finder tabOf(IconData icon) =>
      find.ancestor(of: find.byIcon(icon), matching: find.byType(InkWell));

  double widthOf(WidgetTester tester, IconData icon) =>
      tester.getSize(tabOf(icon)).width;

  Color pillOf(WidgetTester tester, IconData icon) =>
      (tester
                  .widget<Container>(
                    find
                        .ancestor(
                          of: find.byIcon(icon),
                          matching: find.byType(Container),
                        )
                        .first,
                  )
                  .decoration!
              as BoxDecoration)
          .color ??
      Colors.transparent;

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: zunoLightTheme,
      home: child,
    ),
  );

  Iterable<Badge> visibleDots(WidgetTester tester) => tester
      .widgetList<Badge>(find.byType(Badge))
      .where((badge) => badge.isLabelVisible);

  testWidgets('only the selected tab is expanded, named and on a lighter '
      'pill; the other shows just its icon', (tester) async {
    await pump(tester, bar(selected: HomeTab.communities));
    final colors = zunoLightTheme.colorScheme;

    expect(find.text('Communities'), findsOneWidget);
    expect(find.text('Chats'), findsNothing);
    expect(find.byIcon(Icons.workspaces), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    expect(
      widthOf(tester, Icons.workspaces),
      greaterThan(widthOf(tester, Icons.chat_bubble_outline) * 2),
    );
    expect(pillOf(tester, Icons.workspaces), colors.surfaceContainerLowest);
    expect(pillOf(tester, Icons.chat_bubble_outline).a, 0);
  });

  testWidgets('switching tabs moves the expansion across', (tester) async {
    await pump(tester, bar());
    final expanded = widthOf(tester, Icons.chat_bubble);
    final collapsed = widthOf(tester, Icons.workspaces_outlined);

    await pump(tester, bar(selected: HomeTab.communities));
    await tester.pump(ZunoDurations.standard ~/ 2);
    expect(
      widthOf(tester, Icons.chat_bubble_outline),
      allOf(greaterThan(collapsed), lessThan(expanded)),
    );

    await tester.pump(ZunoDurations.standard);
    expect(widthOf(tester, Icons.chat_bubble_outline), collapsed);
    expect(widthOf(tester, Icons.workspaces), expanded);
    expect(find.text('Chats'), findsNothing);
    expect(find.text('Communities'), findsOneWidget);
  });

  testWidgets('with animations off, switching tabs is instant', (tester) async {
    Widget still(HomeTab selected) => Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: bar(selected: selected),
      ),
    );
    await pump(tester, still(HomeTab.chats));
    final expanded = widthOf(tester, Icons.chat_bubble);

    await pump(tester, still(HomeTab.communities));

    expect(widthOf(tester, Icons.workspaces), expanded);
    expect(find.text('Chats'), findsNothing);
  });

  testWidgets('the round button starts something new for the tab', (
    tester,
  ) async {
    var started = 0;
    await pump(tester, bar(onNew: () => started++));

    await tester.tap(find.byTooltip('New chat'));
    expect(started, 1);

    await pump(tester, bar(selected: HomeTab.communities));
    expect(find.byTooltip('New community'), findsOneWidget);
    expect(find.byTooltip('New chat'), findsNothing);
  });

  testWidgets('tapping a tab reports it', (tester) async {
    final chosen = <HomeTab>[];
    await pump(tester, bar(onSelect: chosen.add));

    await tester.tap(find.byIcon(Icons.workspaces_outlined));
    await tester.tap(find.text('Chats'));

    expect(chosen, [HomeTab.communities, HomeTab.chats]);
  });

  testWidgets('a dot marks only the tabs with something unread', (
    tester,
  ) async {
    await pump(tester, bar());
    expect(visibleDots(tester), isEmpty);

    await pump(tester, bar(communitiesUnread: true));
    expect(visibleDots(tester), hasLength(1));
    expect(
      find.ancestor(
        of: find.byIcon(Icons.workspaces_outlined),
        matching: find.byWidgetPredicate((w) => w is Badge && w.isLabelVisible),
      ),
      findsOneWidget,
    );

    await pump(tester, bar(chatsUnread: true, communitiesUnread: true));
    expect(visibleDots(tester), hasLength(2));
  });

  testWidgets('screen readers hear each tab by name, which is selected and '
      'which has something unread', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, bar(communitiesUnread: true));

    expect(
      tester.getSemantics(find.byIcon(Icons.chat_bubble)),
      matchesSemantics(
        label: 'Chats',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.byIcon(Icons.workspaces_outlined)),
      matchesSemantics(
        label: 'Communities',
        value: 'Unread',
        isButton: true,
        hasSelectedState: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('survives the layout matrix', (tester) async {
    for (final selected in HomeTab.values) {
      await expectSurvivesLayoutMatrix(
        tester,
        () =>
            bar(selected: selected, chatsUnread: true, communitiesUnread: true),
        theme: zunoLightTheme,
      );
    }
  });

  testWidgets('the floating call window keeps clear of it', (tester) async {
    await pump(tester, bar(selected: HomeTab.chats));

    expect(
      find.descendant(
        of: find.byType(HomeBottomBar),
        matching: find.byType(KeepClearArea),
      ),
      findsOneWidget,
    );
  });
}
