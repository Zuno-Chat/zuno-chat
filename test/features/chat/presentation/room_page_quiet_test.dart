import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/features/chat/presentation/message_list_view.dart';
import 'package:zuno/features/chat/presentation/room_page.dart';

import 'room_page_harness.dart';

void main() {
  MessageListView list(WidgetTester tester) =>
      tester.widget<MessageListView>(find.byType(MessageListView));

  testWidgets('a sync for another room does not rebuild the list', (
    tester,
  ) async {
    final harness = RoomPageHarness();
    harness.db.events = [harness.message(r'$m1')];
    await harness.pumpRoomPage(tester);
    final before = list(tester);

    harness.client.onSync.add(
      SyncUpdate(
        nextBatch: 's2',
        rooms: RoomsUpdate(join: {'!other:example.org': JoinedRoomUpdate()}),
      ),
    );
    await tester.pump();
    expect(identical(list(tester), before), isTrue);

    harness.client.onSync.add(
      SyncUpdate(
        nextBatch: 's3',
        rooms: RoomsUpdate(join: {harness.room.id: JoinedRoomUpdate()}),
      ),
    );
    await tester.pump();
    expect(identical(list(tester), before), isFalse);
  });

  testWidgets('a recording tick does not rebuild the list', (tester) async {
    final harness = RoomPageHarness();
    harness.db.events = [harness.message(r'$m1')];
    await harness.pumpRoomPage(tester);
    final before = list(tester);

    final state = tester.state(find.byType(RoomPage)) as dynamic;
    (state.recordingDuration as ValueNotifier<Duration>).value = const Duration(
      seconds: 3,
    );
    await tester.pump();

    expect(identical(list(tester), before), isTrue);
  });

  testWidgets('the scroll button toggles without rebuilding the list', (
    tester,
  ) async {
    final harness = RoomPageHarness();
    harness.db.events = [
      for (var i = 40; i > 0; i--)
        harness.message(
          '\$m$i',
          body: 'message number $i',
          at: DateTime(2026, 9, 20, 12).add(Duration(minutes: i * 10)),
        ),
    ];
    await harness.pumpRoomPage(tester);
    final before = list(tester);
    expect(find.byTooltip('Scroll to latest'), findsNothing);

    await tester.drag(find.byType(MessageListView), const Offset(0, 500));
    await tester.pump();

    expect(find.byTooltip('Scroll to latest'), findsOneWidget);
    expect(identical(list(tester), before), isTrue);
  });
}
