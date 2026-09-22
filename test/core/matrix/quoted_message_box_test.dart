import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/matrix/quoted_message_box.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Align(child: child)),
    ),
  );

  testWidgets('renders sender name and snippet with no paint error', (
    tester,
  ) async {
    await pump(
      tester,
      const QuotedMessageBox(senderName: 'Alice', snippet: 'See you then'),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('See you then'), findsOneWidget);
  });

  testWidgets('still renders with an empty snippet', (tester) async {
    await pump(tester, const QuotedMessageBox(senderName: 'Bob', snippet: ''));

    expect(tester.takeException(), isNull);
    expect(find.text('Bob'), findsOneWidget);
  });

  testWidgets('renders in dark mode with no paint error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: Align(
            child: QuotedMessageBox(senderName: 'Carol', snippet: 'On my way'),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Carol'), findsOneWidget);
  });

  testWidgets('shows the icon next to the label for an image/video reply', (
    tester,
  ) async {
    await pump(
      tester,
      const QuotedMessageBox(
        senderName: 'Dave',
        snippet: 'Photo',
        icon: Icons.photo_outlined,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.photo_outlined), findsOneWidget);
    expect(find.text('Photo'), findsOneWidget);
  });

  testWidgets('shows a thumbnail alongside the icon for an image/video reply', (
    tester,
  ) async {
    const thumbnailKey = Key('reply-thumbnail');
    await pump(
      tester,
      QuotedMessageBox(
        senderName: 'Erin',
        snippet: 'Video',
        icon: Icons.videocam_outlined,
        thumbnail: Container(key: thumbnailKey, color: Colors.black),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.videocam_outlined), findsOneWidget);
    expect(find.byKey(thumbnailKey), findsOneWidget);
  });

  testWidgets('plain text reply has no icon and no thumbnail', (tester) async {
    await pump(
      tester,
      const QuotedMessageBox(senderName: 'Frank', snippet: 'Hey'),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Hey'), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('defaults to the small-card radius (8) with no radius given', (
    tester,
  ) async {
    await pump(
      tester,
      const QuotedMessageBox(senderName: 'Grace', snippet: 'Hi'),
    );

    final decoration =
        tester.widget<Container>(find.byType(Container).first).decoration
            as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(8));
  });

  testWidgets('matches the bubble radius when one is passed', (tester) async {
    await pump(
      tester,
      const QuotedMessageBox(
        senderName: 'Heidi',
        snippet: 'On the way',
        borderRadius: 18,
      ),
    );

    final decoration =
        tester.widget<Container>(find.byType(Container).first).decoration
            as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(18));
  });
}
