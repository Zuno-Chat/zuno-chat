import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/matrix/quoted_message_box.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Align(child: child)),
    ),
  );

  testWidgets('a plain text reply shows sender name and snippet, with no '
      'icon', (tester) async {
    await pump(
      tester,
      const QuotedMessageBox(senderName: 'Alice', snippet: 'See you then'),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('See you then'), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
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
}
