import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/media_pill.dart';
import 'package:zuno/core/ui/zuno_colors.dart';

void main() {
  Future<BuildContext> pump(WidgetTester tester, MediaPillSize size) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MediaPill(
              size: size,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [Icon(Icons.play_arrow), Text('0:42')],
              ),
            ),
          ),
        ),
      ),
    );
    return tester.element(find.text('0:42'));
  }

  testWidgets('a regular pill shows its content in on-media label text', (
    tester,
  ) async {
    final context = await pump(tester, MediaPillSize.regular);
    final theme = Theme.of(context);
    final style = DefaultTextStyle.of(context).style;

    expect(style.color, onMediaColor);
    expect(style.fontSize, theme.textTheme.labelMedium!.fontSize);
    expect(IconTheme.of(context).size, 16);
    expect(IconTheme.of(context).color, onMediaColor);
  });

  testWidgets('a small pill uses the smaller label and icon', (tester) async {
    final context = await pump(tester, MediaPillSize.small);
    final theme = Theme.of(context);

    expect(
      DefaultTextStyle.of(context).style.fontSize,
      theme.textTheme.labelSmall!.fontSize,
    );
    expect(IconTheme.of(context).size, 14);
  });

  testWidgets('the pill sits on the media scrim', (tester) async {
    await pump(tester, MediaPillSize.regular);
    final box = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(MediaPill),
        matching: find.byType(DecoratedBox),
      ),
    );

    expect((box.decoration as BoxDecoration).color, mediaScrimColor);
  });
}
