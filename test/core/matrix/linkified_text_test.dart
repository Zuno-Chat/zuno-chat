import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/linkified_text.dart';
import 'package:zuno/core/ui/zuno_colors.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

List<TextSpan> _spans(WidgetTester tester) {
  final span = tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan;
  return span.children!.whereType<TextSpan>().toList();
}

void main() {
  testWidgets(
    'plain text with no URL or mention renders as a single unstyled span',
    (tester) async {
      await tester.pumpWidget(
        _wrap(const LinkifiedText('just a normal message')),
      );
      expect(find.text('just a normal message'), findsOneWidget);
      final text = tester.widget<Text>(find.byType(Text));
      expect(text.textSpan, isNull);
    },
  );

  testWidgets('highlights a standalone @room mention in the primary color', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const LinkifiedText('@room please read this')),
    );
    final context = tester.element(find.byType(LinkifiedText));
    final primary = Theme.of(context).colorScheme.primary;

    final mentionSpan = _spans(tester).firstWhere((s) => s.text == '@room');
    expect(mentionSpan.style!.color, primary);
    expect(mentionSpan.style!.fontWeight, FontWeight.bold);
    expect(mentionSpan.recognizer, isNull);
  });

  testWidgets("doesn't highlight @room as a substring of a longer word", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const LinkifiedText('ask your @roommate about it')),
    );
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.textSpan, isNull);
    expect(find.text('ask your @roommate about it'), findsOneWidget);
  });

  testWidgets('highlights a URL and a @room mention in the same message', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const LinkifiedText('@room see https://example.com for details')),
    );
    final children = _spans(tester);

    final mentionSpan = children.firstWhere((s) => s.text == '@room');
    final linkSpan = children.firstWhere(
      (s) => s.text == 'https://example.com',
    );
    expect(mentionSpan.style!.fontWeight, FontWeight.bold);
    expect(linkSpan.recognizer, isA<TapGestureRecognizer>());
    expect(linkSpan.style!.decoration, isNot(TextDecoration.underline));
    expect(linkSpan.style!.color, ZunoColors.light.link);
  });

  testWidgets('highlights @mentions of room members only', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const LinkifiedText(
          'hi @alice, @Nobody and foo@bar',
          mentionable: {'@alice', '@bar'},
        ),
      ),
    );
    final children = _spans(tester);

    final alice = children.firstWhere((s) => s.text == '@alice');
    expect(alice.style!.fontWeight, FontWeight.bold);
    expect(alice.recognizer, isNull);
    expect(children.any((s) => s.text == '@Nobody'), isFalse);
    expect(children.any((s) => s.text == '@bar'), isFalse);
  });

  testWidgets('highlights a bracketed display-name mention', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const LinkifiedText(
          'hi @[Alice Smith]!',
          mentionable: {'@[alice smith]'},
        ),
      ),
    );
    final children = _spans(tester);

    expect(
      children.firstWhere((s) => s.text == '@[Alice Smith]').style!.fontWeight,
      FontWeight.bold,
    );
  });

  testWidgets('highlights a mention whose localpart holds a hyphen', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const LinkifiedText('hi @bob-smith!', mentionable: {'@bob-smith'})),
    );
    final children = _spans(tester);

    expect(
      children.firstWhere((s) => s.text == '@bob-smith').style!.fontWeight,
      FontWeight.bold,
    );
  });

  testWidgets('a mention never shows the server name', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const LinkifiedText(
          'hi @bob:zuno.chat and @bob-smith:zuno.chat!',
          mentionable: {'@bob', '@bob-smith'},
        ),
      ),
    );
    final children = _spans(tester);

    expect(
      children.firstWhere((s) => s.text == '@bob').style!.fontWeight,
      FontWeight.bold,
    );
    expect(
      children.firstWhere((s) => s.text == '@bob-smith').style!.fontWeight,
      FontWeight.bold,
    );
    expect(children.any((s) => (s.text ?? '').contains('zuno.chat')), isFalse);
  });

  testWidgets('a bracketed mention keeps the words that follow the colon', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const LinkifiedText(
          'hi @[Alice Smith]:hello',
          mentionable: {'@[alice smith]'},
        ),
      ),
    );
    final children = _spans(tester);

    expect(children.any((s) => (s.text ?? '').contains(':hello')), isTrue);
  });

  testWidgets('a name that is nobody in the room keeps its server', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const LinkifiedText('hi @nobody:zuno.chat', mentionable: {'@bob'})),
    );

    expect(find.text('hi @nobody:zuno.chat'), findsOneWidget);
  });

  testWidgets('leaves @mentions plain when no members are known', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const LinkifiedText('hi @alice')));

    expect(find.text('hi @alice'), findsOneWidget);
    expect(tester.widget<Text>(find.byType(Text)).textSpan, isNull);
  });

  testWidgets('a trailing span is appended after plain text', (tester) async {
    const trailing = WidgetSpan(child: SizedBox(width: 30, height: 1));
    await tester.pumpWidget(
      _wrap(const LinkifiedText('just text', trailing: trailing)),
    );
    final span = tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan;
    expect((span.children!.first as TextSpan).text, 'just text');
    expect(span.children!.last, same(trailing));
  });

  testWidgets('a trailing span is appended after a link', (tester) async {
    const trailing = WidgetSpan(child: SizedBox(width: 30, height: 1));
    await tester.pumpWidget(
      _wrap(const LinkifiedText('see https://example.com', trailing: trailing)),
    );
    final span = tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan;
    expect(span.children!.last, same(trailing));
  });

  testWidgets('links take the dark theme token in the dark', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: const Scaffold(body: LinkifiedText('see https://example.com')),
      ),
    );
    final link = _spans(tester)
        .firstWhere((s) => s.text == 'https://example.com');
    expect(link.style!.color, ZunoColors.dark.link);
  });
}
