import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/zuno_colors.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/chat/presentation/message_meta.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: zunoLightTheme,
  home: Scaffold(body: Center(child: child)),
);

Icon _icon(WidgetTester tester) => tester.widget<Icon>(find.byType(Icon));

void main() {
  final colors = zunoLightTheme.colorScheme;
  final zuno = zunoLightTheme.extension<ZunoColors>()!;

  testWidgets(
    'sending shows a clock, sent a tick, read a double tick in primary',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MessageMeta(
            time: '09:41',
            own: true,
            status: MetaStatus.sending,
          ),
        ),
      );
      expect(_icon(tester).icon, Icons.schedule);
      expect(_icon(tester).color, zuno.onBubbleOutgoingVariant);

      await tester.pumpWidget(
        _wrap(
          const MessageMeta(time: '09:41', own: true, status: MetaStatus.sent),
        ),
      );
      expect(_icon(tester).icon, Icons.done);
      expect(_icon(tester).color, zuno.onBubbleOutgoingVariant);

      await tester.pumpWidget(
        _wrap(
          const MessageMeta(time: '09:41', own: true, status: MetaStatus.read),
        ),
      );
      expect(_icon(tester).icon, Icons.done_all);
      expect(_icon(tester).color, colors.primary);

      await tester.pumpWidget(
        _wrap(const MessageMeta(time: '09:41', own: true)),
      );
      expect(find.byType(Icon), findsNothing);
    },
  );

  testWidgets(
    'own meta uses the outgoing variant color, other meta onSurfaceVariant',
    (tester) async {
      await tester.pumpWidget(
        _wrap(const MessageMeta(time: '09:41', own: true)),
      );
      expect(
        tester.widget<Text>(find.text('09:41')).style!.color,
        zuno.onBubbleOutgoingVariant,
      );

      await tester.pumpWidget(
        _wrap(const MessageMeta(time: '09:41', own: false, edited: true)),
      );
      expect(
        tester.widget<Text>(find.text('09:41')).style!.color,
        colors.onSurfaceVariant,
      );
      final edited = tester.widget<Text>(find.text('edited'));
      expect(edited.style!.fontStyle, FontStyle.italic);
      expect(edited.style!.color, colors.onSurfaceVariant);
    },
  );

  testWidgets('on media the text is white and the read tick primaryContainer', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const MessageMeta(
          time: '09:41',
          own: true,
          status: MetaStatus.read,
          onMedia: true,
        ),
      ),
    );
    expect(tester.widget<Text>(find.text('09:41')).style!.color, Colors.white);
    expect(_icon(tester).color, colors.primaryContainer);

    await tester.pumpWidget(
      _wrap(
        const MessageMeta(
          time: '09:41',
          own: true,
          status: MetaStatus.sent,
          onMedia: true,
        ),
      ),
    );
    expect(_icon(tester).color, Colors.white70);
  });

  group('tucked meta', () {
    const style = TextStyle(fontSize: 16, height: 1.3);

    Widget tucked(String text) => _wrap(
      SizedBox(
        width: 246,
        child: Align(
          alignment: Alignment.topLeft,
          child: TuckedMeta(
            meta: const MessageMeta(time: '09:41', own: false),
            textBuilder: (spacer) => Text.rich(
              TextSpan(text: text, children: [spacer]),
              style: style,
            ),
          ),
        ),
      ),
    );

    testWidgets('short text keeps the meta on the last line', (tester) async {
      await tester.pumpWidget(tucked('Hi'));
      final box = tester.getRect(find.byType(TuckedMeta));
      expect(box.height, closeTo(20.8, 0.5));
      final meta = tester.getRect(find.byType(MessageMeta).last);
      expect(meta.right, closeTo(box.right, 0.01));
      expect(meta.bottom, closeTo(box.bottom, 0.01));
    });

    testWidgets('a full last line pushes the meta below', (tester) async {
      await tester.pumpWidget(tucked('A' * 15));
      final box = tester.getRect(find.byType(TuckedMeta));
      expect(box.height, greaterThan(21));
      expect(box.height, lessThanOrEqualTo(42));
    });

    for (final scale in [0.85, 1.3, 2.0]) {
      testWidgets('the twin reserves the meta width at text scale $scale', (
        tester,
      ) async {
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: tucked('Hi'),
          ),
        );
        final metas = find.byType(MessageMeta);
        final visible = tester.getSize(metas.last);
        final total = tester.getSize(find.byType(TuckedMeta));
        final reserved = total.width - 2 * 16 * scale;

        expect(metas, findsNWidgets(2));
        expect(reserved, greaterThanOrEqualTo(visible.width));
        expect(reserved, lessThan(visible.width * 1.2 + 8 * scale));
        expect(total.height, closeTo(20.8 * scale, 0.6));
      });
    }

    testWidgets('the invisible twin is kept out of semantics', (tester) async {
      await tester.pumpWidget(tucked('Hi'));
      expect(find.bySemanticsLabel('09:41'), findsOneWidget);
    });
  });
}
