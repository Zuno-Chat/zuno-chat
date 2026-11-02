import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/features/chat/presentation/date_divider.dart';
import 'package:zuno/features/chat/presentation/message_bubble.dart';
import 'package:zuno/features/chat/presentation/message_list_view.dart';

import 'room_page_harness.dart';

void main() {
  late RoomPageHarness harness;

  Future<void> openRoomTyping(WidgetTester tester, int messages) async {
    harness = RoomPageHarness();
    harness.db.events = [
      for (var i = 0; i < messages; i++)
        harness.message(
          '\$m$i',
          body: 'message $i',
          at: DateTime(2026, 9, 20, 12, i),
        ),
    ];
    await harness.pumpRoomPage(tester);
    await tester.showKeyboard(find.byType(TextField));
    await tester.pump();
  }

  bool typing(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus;

  testWidgets('a tap on empty space in the chat closes the keyboard', (
    tester,
  ) async {
    await openRoomTyping(tester, 1);
    expect(typing(tester), isTrue);

    await tester.tapAt(
      tester.getTopLeft(find.byType(MessageListView)) + const Offset(24, 24),
    );
    await harness.settle(tester);

    expect(typing(tester), isFalse);
  });

  testWidgets('a tap on a date divider closes the keyboard', (tester) async {
    await openRoomTyping(tester, 1);

    await tester.tap(find.byType(DateDivider).first);
    await harness.settle(tester);

    expect(typing(tester), isFalse);
  });

  testWidgets('a tap on a message keeps the keyboard open', (tester) async {
    await openRoomTyping(tester, 1);

    await tester.tap(
      find.ancestor(
        of: find.textContaining('message 0', findRichText: true),
        matching: find.byType(MessageBubble),
      ),
    );
    await harness.settle(tester);

    expect(typing(tester), isTrue);
  });

  testWidgets('a tap that stops a fling keeps the keyboard open', (
    tester,
  ) async {
    await openRoomTyping(tester, 60);

    await tester.fling(
      find.byType(MessageListView),
      const Offset(0, 400),
      3000,
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tapAt(tester.getCenter(find.byType(MessageListView)));
    await harness.settle(tester);

    expect(typing(tester), isTrue);
  });

  testWidgets('scrolling the chat keeps the keyboard open', (tester) async {
    await openRoomTyping(tester, 40);

    await tester.drag(find.byType(MessageListView), const Offset(0, 300));
    await harness.settle(tester);

    expect(typing(tester), isTrue);
  });
}
