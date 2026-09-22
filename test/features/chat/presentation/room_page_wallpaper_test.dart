import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/features/chat/presentation/chat_wallpaper.dart';
import 'package:zuno/features/chat/presentation/message_list_view.dart';

import 'room_page_harness.dart';

void main() {
  testWidgets('every chat has the one wallpaper, behind the messages', (
    tester,
  ) async {
    final harness = RoomPageHarness();
    harness.db.events = [harness.message(r'$m1')];
    await harness.pumpRoomPage(tester);

    expect(find.byType(ChatWallpaperBackground), findsOneWidget);
    final stack = tester.widget<Stack>(
      find
          .ancestor(
            of: find.byType(ChatWallpaperBackground),
            matching: find.byType(Stack),
          )
          .first,
    );
    expect(stack.children.first, isA<ChatWallpaperBackground>());
    expect(find.byType(MessageListView), findsOneWidget);
  });

  testWidgets('the chat menu no longer offers a wallpaper choice', (
    tester,
  ) async {
    final harness = RoomPageHarness();
    harness.db.events = [harness.message(r'$m1')];
    await harness.pumpRoomPage(tester);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Add to home screen'), findsOneWidget);
    expect(find.text('Chat wallpaper'), findsNothing);
  });
}
