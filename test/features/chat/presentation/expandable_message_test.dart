import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/features/chat/presentation/expandable_message.dart';

void main() {
  group('shouldCollapseMessage', () {
    test('leaves an ordinary message alone', () {
      expect(shouldCollapseMessage('hey, are you free later?'), isFalse);
    });

    test('collapses one very long paragraph', () {
      expect(
        shouldCollapseMessage('a' * (collapsedMessageMaxChars + 1)),
        isTrue,
      );
    });

    test('collapses many short lines', () {
      final lines = List.filled(collapsedMessageMaxLines + 1, 'x').join('\n');
      expect(shouldCollapseMessage(lines), isTrue);
    });

    test('a message exactly at both limits still renders in full', () {
      final lines = List.filled(collapsedMessageMaxLines, 'x').join('\n');
      expect(shouldCollapseMessage(lines), isFalse);
      expect(shouldCollapseMessage('a' * collapsedMessageMaxChars), isFalse);
    });
  });

  Future<int?> pumpFor(WidgetTester tester, String text) async {
    int? lastMaxLines;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExpandableMessage(
            text: text,
            builder: (context, maxLines) {
              lastMaxLines = maxLines;
              return Text(text, maxLines: maxLines);
            },
          ),
        ),
      ),
    );
    return lastMaxLines;
  }

  testWidgets('a short message has no toggle and no line limit', (
    tester,
  ) async {
    expect(await pumpFor(tester, 'hello'), isNull);
    expect(find.text('Read more'), findsNothing);
  });

  testWidgets('a long message starts clamped and expands on tap', (
    tester,
  ) async {
    final long = 'a' * (collapsedMessageMaxChars + 1);

    expect(await pumpFor(tester, long), collapsedMessageMaxLines);
    expect(find.text('Read more'), findsOneWidget);

    await tester.tap(find.text('Read more'));
    await tester.pump();

    expect(tester.widget<Text>(find.text(long)).maxLines, isNull);
    expect(find.text('Show less'), findsOneWidget);
  });
}
