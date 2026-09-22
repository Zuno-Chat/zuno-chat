import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/room_exit.dart';
import 'package:zuno/features/chat/presentation/room_page.dart';
import 'package:zuno/features/room_info/presentation/room_info_page.dart';

import 'room_page_harness.dart';

void main() {
  Future<RoomPageHarness> openInfo(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final harness = RoomPageHarness();
    harness.room.summary.mJoinedMemberCount = 2;
    harness.db.events = [harness.message(r'$m1')];
    await tester.pumpWidget(
      await harness.app(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RoomPage(room: harness.room),
                ),
              ),
              child: const Text('open chat'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open chat'));
    await harness.settle(tester);

    await tester.tap(find.byTooltip('Show menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Room info'));
    await harness.settle(tester);
    expect(find.byType(RoomInfoPage), findsOneWidget);
    return harness;
  }

  testWidgets('leaving from room info closes the info page and the chat', (
    tester,
  ) async {
    final harness = await openInfo(tester);

    await tester.tap(find.text(roomExitLabel(harness.room)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byType(TextButton).last);
    await harness.settle(tester);
    await tester.pump(const Duration(seconds: 1));

    expect(
      harness.requests.where((path) => path.endsWith('/leave')),
      hasLength(1),
    );
    expect(find.byType(RoomInfoPage), findsNothing);
    expect(find.byType(RoomPage), findsNothing);
    expect(find.text('open chat'), findsOneWidget);
  });

  testWidgets('a call from room info goes back to the chat and starts there', (
    tester,
  ) async {
    await openInfo(tester);

    await tester.tap(find.byTooltip('Voice call'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(RoomInfoPage), findsNothing);
    expect(find.byType(RoomPage), findsOneWidget);
  });

  testWidgets('room info alone in a chat offers no call', (tester) async {
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final harness = RoomPageHarness();
    harness.room.setState(
      User('@bob:example.org', membership: 'leave', room: harness.room),
    );
    harness.db.events = [harness.message(r'$m1')];
    await harness.pumpRoomPage(tester);

    await tester.tap(find.byTooltip('Show menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Room info'));
    await harness.settle(tester);

    expect(find.byType(RoomInfoPage), findsOneWidget);
    expect(find.byTooltip('Voice call'), findsNothing);
  });
}
