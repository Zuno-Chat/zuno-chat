import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/zuno_colors.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/chat/presentation/message_bubble.dart';

import '../../../helpers/contrast.dart';

Widget _wrap(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? zunoLightTheme,
  home: Scaffold(body: Center(child: child)),
);

Material _bubbleMaterial(WidgetTester tester) => tester.widget<Material>(
  find
      .descendant(
        of: find.byType(MessageBubble),
        matching: find.byType(Material),
      )
      .first,
);

void main() {
  test('corners for every side and position', () {
    const big = Radius.circular(20);
    const small = Radius.circular(6);
    BorderRadius r(bool own, RunPosition p) =>
        bubbleRadius(own: own, position: p);

    expect(r(true, RunPosition.single), const BorderRadius.all(big));
    expect(r(false, RunPosition.single), const BorderRadius.all(big));
    expect(
      r(true, RunPosition.first),
      const BorderRadius.only(
        topLeft: big,
        bottomLeft: big,
        topRight: big,
        bottomRight: small,
      ),
    );
    expect(
      r(true, RunPosition.middle),
      const BorderRadius.only(
        topLeft: big,
        bottomLeft: big,
        topRight: small,
        bottomRight: small,
      ),
    );
    expect(
      r(true, RunPosition.last),
      const BorderRadius.only(
        topLeft: big,
        bottomLeft: big,
        topRight: small,
        bottomRight: big,
      ),
    );
    expect(
      r(false, RunPosition.first),
      const BorderRadius.only(
        topRight: big,
        bottomRight: big,
        topLeft: big,
        bottomLeft: small,
      ),
    );
    expect(
      r(false, RunPosition.middle),
      const BorderRadius.only(
        topRight: big,
        bottomRight: big,
        topLeft: small,
        bottomLeft: small,
      ),
    );
    expect(
      r(false, RunPosition.last),
      const BorderRadius.only(
        topRight: big,
        bottomRight: big,
        topLeft: small,
        bottomLeft: big,
      ),
    );
  });

  test('the run flags map to a position', () {
    expect(RunPosition.of(startsRun: true, endsRun: true), RunPosition.single);
    expect(RunPosition.of(startsRun: true, endsRun: false), RunPosition.first);
    expect(
      RunPosition.of(startsRun: false, endsRun: false),
      RunPosition.middle,
    );
    expect(RunPosition.of(startsRun: false, endsRun: true), RunPosition.last);
  });

  test('every text color passes on both bubbles and both quote fills', () {
    for (final theme in [zunoLightTheme, zunoDarkTheme]) {
      final colors = theme.colorScheme;
      final zuno = theme.extension<ZunoColors>()!;
      for (final own in [true, false]) {
        final fill = bubbleFill(theme, own: own);
        final quote = quoteFill(surface: colors.surface, bubble: fill);
        for (final surface in [fill, quote]) {
          for (final text in [
            bubbleInk(theme, own: own),
            bubbleMuted(theme, own: own),
            colors.primary,
            colors.error,
            zuno.link,
          ]) {
            expect(
              contrastRatio(text, surface),
              greaterThanOrEqualTo(4.5),
              reason: '$text on $surface (${theme.brightness}, own: $own)',
            );
          }
        }
      }
    }
  });

  testWidgets('own bubble uses bubbleOutgoing, other surfaceContainerHigh', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const MessageBubble(
          own: true,
          position: RunPosition.single,
          child: Text('hi'),
        ),
      ),
    );
    expect(_bubbleMaterial(tester).color, ZunoColors.light.bubbleOutgoing);
    expect(
      tester.widget<RichText>(find.byType(RichText)).text.style!.color,
      ZunoColors.light.onBubbleOutgoing,
    );

    await tester.pumpWidget(
      _wrap(
        const MessageBubble(
          own: false,
          position: RunPosition.single,
          child: Text('hi'),
        ),
      ),
    );
    expect(
      _bubbleMaterial(tester).color,
      zunoLightTheme.colorScheme.surfaceContainerHigh,
    );
  });

  testWidgets('message text is 16 px at 1.3 line height', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const MessageBubble(
          own: false,
          position: RunPosition.single,
          child: Text('hi'),
        ),
      ),
    );
    final style = tester.widget<RichText>(find.byType(RichText)).text.style!;
    expect(style.fontSize, 16);
    expect(style.height, 1.3);
    expect(style.letterSpacing, 0.2);
  });

  testWidgets('the sender name shows only when given, in primary at 500', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const MessageBubble(
          own: false,
          position: RunPosition.first,
          senderName: 'Maya',
          child: Text('hi'),
        ),
      ),
    );
    final name = tester.widget<Text>(find.text('Maya'));
    expect(name.style!.color, zunoLightTheme.colorScheme.primary);
    expect(name.style!.fontWeight, FontWeight.w500);

    await tester.pumpWidget(
      _wrap(
        const MessageBubble(
          own: false,
          position: RunPosition.middle,
          child: Text('hi'),
        ),
      ),
    );
    expect(find.text('Maya'), findsNothing);
  });

  testWidgets('taps and long presses reach the callbacks through ink', (
    tester,
  ) async {
    var taps = 0;
    var holds = 0;
    await tester.pumpWidget(
      _wrap(
        MessageBubble(
          own: true,
          position: RunPosition.single,
          onTap: () => taps++,
          onLongPress: () => holds++,
          child: const Text('hi'),
        ),
      ),
    );
    final ink = find.descendant(
      of: find.byType(MessageBubble),
      matching: find.byType(InkWell),
    );
    expect(ink, findsOneWidget);
    await tester.tap(find.text('hi'));
    await tester.longPress(find.text('hi'));
    expect(taps, 1);
    expect(holds, 1);
  });

  testWidgets('only a bubble with a quote pays for IntrinsicWidth', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const MessageBubble(
          own: true,
          position: RunPosition.single,
          child: Text('hi'),
        ),
      ),
    );
    expect(find.byType(IntrinsicWidth), findsNothing);

    await tester.pumpWidget(
      _wrap(
        const MessageBubble(
          own: true,
          position: RunPosition.single,
          quote: Text('quoted'),
          child: Text('hi'),
        ),
      ),
    );
    expect(find.byType(IntrinsicWidth), findsOneWidget);
  });
}
