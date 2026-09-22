import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'room_page_harness.dart';

void main() {
  testWidgets('the attachment menu offers Location once someone has joined', (
    tester,
  ) async {
    final harness = RoomPageHarness();
    harness.db.events = [harness.message(r'$m1')];
    await harness.pumpRoomPage(tester);

    await tester.tap(find.byIcon(Icons.attach_file_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Choose file'), findsOneWidget);
    expect(find.text('Location'), findsOneWidget);
  });

  testWidgets('alone in the chat, the menu still offers Location', (
    tester,
  ) async {
    final harness = RoomPageHarness();
    harness.room.setState(
      User('@bob:example.org', membership: 'leave', room: harness.room),
    );
    harness.db.events = [harness.message(r'$m1')];
    await harness.pumpRoomPage(tester);

    await tester.tap(find.byIcon(Icons.attach_file_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Location'), findsOneWidget);
    expect(find.byTooltip('Voice call'), findsNothing);
  });
}
