import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/ui/step_hero.dart';
import 'package:zuno/core/ui/step_layout.dart';
import 'package:zuno/core/ui/zuno_theme.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(360, 640),
    double keyboard = 0,
    List<Widget> children = const [],
    String? body = 'One paragraph that says why.',
    bool actionsFollowContent = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: zunoLightTheme,
        home: Scaffold(
          body: StepLayout(
            hero: const StepHero(icon: Icons.shield_outlined),
            title: 'Keep your messages',
            body: body,
            actionsFollowContent: actionsFollowContent,
            actions: [
              FilledButton(onPressed: () {}, child: const Text('Continue')),
              TextButton(onPressed: () {}, child: const Text('Not now')),
            ],
            children: children,
          ),
        ),
      ),
    );
  }

  testWidgets('centres the circle, the title and the text', (tester) async {
    await pump(tester);

    expect(tester.getCenter(find.byType(StepHero)).dx, closeTo(180, 1));
    for (final text in ['Keep your messages', 'One paragraph that says why.']) {
      expect(tester.widget<Text>(find.text(text)).textAlign, TextAlign.center);
    }
  });

  testWidgets('pins full-width actions to the bottom, in order', (
    tester,
  ) async {
    await pump(tester);

    final primary = tester.getRect(find.byType(FilledButton));
    final secondary = tester.getRect(find.byType(TextButton));
    expect(primary.width, 360 - 48);
    expect(secondary.top, greaterThanOrEqualTo(primary.bottom));
    expect(secondary.bottom, closeTo(640 - 16, 0.5));
  });

  testWidgets('actions that follow the content sit right under the text and '
      'the group is centred', (tester) async {
    await pump(tester, size: const Size(360, 800), actionsFollowContent: true);

    final hero = tester.getRect(find.byType(StepHero));
    final text = tester.getRect(find.text('One paragraph that says why.'));
    final primary = tester.getRect(find.byType(FilledButton));
    final secondary = tester.getRect(find.byType(TextButton));
    expect(primary.top - text.bottom, closeTo(16, 0.5));
    expect(primary.width, 360 - 48);
    expect(secondary.top, greaterThanOrEqualTo(primary.bottom));
    expect(hero.top - 16, closeTo(800 - 16 - secondary.bottom, 1));
  });

  testWidgets('actions that follow the content still stay on screen when the '
      'content is taller than the room left', (tester) async {
    await pump(
      tester,
      actionsFollowContent: true,
      children: const [SizedBox(height: 600)],
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byType(TextButton)).bottom,
      closeTo(640 - 16, 0.5),
    );
    expect(find.byType(Scrollable), findsOneWidget);
  });

  testWidgets('extra content sits between the text and the actions', (
    tester,
  ) async {
    await pump(
      tester,
      children: const [SizedBox(key: ValueKey('extra'), height: 40)],
    );

    final extra = tester.getRect(find.byKey(const ValueKey('extra')));
    expect(
      extra.top,
      greaterThan(
        tester.getRect(find.text('One paragraph that says why.')).bottom,
      ),
    );
    expect(
      extra.bottom,
      lessThan(tester.getRect(find.byType(FilledButton)).top),
    );
  });

  testWidgets('with the keyboard open the middle scrolls and the actions '
      'stay in view', (tester) async {
    await pump(
      tester,
      keyboard: 300,
      children: const [TextField(), SizedBox(height: 12), TextField()],
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.byType(TextButton)).bottom,
      lessThanOrEqualTo(640 - 300),
    );
    await tester.ensureVisible(find.byType(TextField).last);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a step without a paragraph leaves no gap for one', (
    tester,
  ) async {
    await pump(
      tester,
      body: null,
      children: const [SizedBox(key: ValueKey('extra'), height: 40)],
    );

    expect(
      tester.getRect(find.byKey(const ValueKey('extra'))).top -
          tester.getRect(find.text('Keep your messages')).bottom,
      closeTo(24, 0.5),
    );
  });

  testWidgets('on a very short screen everything scrolls as one, so the text '
      'is not squeezed out by the actions', (tester) async {
    await pump(tester, size: const Size(640, 200));

    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsOneWidget);
    final scrollable = tester.getRect(find.byType(Scrollable));
    expect(scrollable.height, greaterThan(150));
    expect(
      find.descendant(
        of: find.byType(Scrollable),
        matching: find.byType(FilledButton),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byType(TextButton));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tall stack of actions at a large font size also falls back '
      'to one scroll', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 330);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: zunoLightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: StepLayout(
            hero: const StepHero(icon: Icons.shield_outlined),
            title: 'Keep your messages',
            actions: [
              for (final label in ['One', 'Two', 'Three', 'Four'])
                TextButton(onPressed: () {}, child: Text(label)),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      find.descendant(of: find.byType(Scrollable), matching: find.text('Four')),
      findsOneWidget,
    );
  });
}
