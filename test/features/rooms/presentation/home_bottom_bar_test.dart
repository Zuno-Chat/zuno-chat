import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

  BoxDecoration pillOf(WidgetTester tester, String label) =>
      tester
              .widget<AnimatedContainer>(
                find.ancestor(
                  of: find.text(label),
                  matching: find.byType(AnimatedContainer),
                ),
              )
              .decoration!
          as BoxDecoration;

  Future<void> pump(WidgetTester tester, Widget child) =>
      tester.pumpWidget(MaterialApp(theme: zunoLightTheme, home: child));

  Iterable<Badge> visibleDots(WidgetTester tester) => tester
      .widgetList<Badge>(find.byType(Badge))
      .where((badge) => badge.isLabelVisible);

  testWidgets('both tabs are named and the selected one is filled and bold', (
    tester,
  ) async {
    await pump(tester, bar(selected: HomeTab.communities));

    expect(find.text('Chats'), findsOneWidget);
    expect(find.text('Communities'), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    expect(find.byIcon(Icons.workspaces), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Communities')).style?.fontWeight,
      FontWeight.w700,
    );
    expect(
      tester.widget<Text>(find.text('Chats')).style?.fontWeight,
      FontWeight.w500,
    );
  });

  testWidgets('the selected tab sits in a lighter pill inside the bar', (
    tester,
  ) async {
    await pump(tester, bar(selected: HomeTab.communities));
    final colors = zunoLightTheme.colorScheme;

    expect(pillOf(tester, 'Communities').color, colors.surfaceContainerLowest);
    expect(pillOf(tester, 'Chats').color, isNull);
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

    await tester.tap(find.text('Communities'));
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

  testWidgets('screen readers hear which tab is selected and which has '
      'something unread', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, bar(communitiesUnread: true));

    expect(
      tester.getSemantics(find.text('Chats')),
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
      tester.getSemantics(find.text('Communities')),
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
    await expectSurvivesLayoutMatrix(
      tester,
      () => bar(chatsUnread: true, communitiesUnread: true),
      theme: zunoLightTheme,
    );
  });
}
