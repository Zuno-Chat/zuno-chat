import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/features/chat/presentation/message_tile.dart';
import 'package:zuno/features/chat/presentation/room_page.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/gated_timeline_database.dart';
import '../../../helpers/route_launcher.dart';
import 'room_page_harness.dart';

void main() {
  testWidgets('the timeline is not applied while the route animates', (
    tester,
  ) async {
    final harness = RoomPageHarness();
    harness.db.events = [
      buildTestEvent(
        harness.room,
        eventId: r'$m1',
        senderId: '@bob:example.org',
        originServerTs: DateTime(2026, 9, 20, 12),
        status: EventStatus.synced,
        content: {
          'msgtype': 'm.text',
          'body': 'hello',
          'm.relates_to': {
            'm.in_reply_to': {'event_id': r'$gone'},
          },
        },
      ),
    ];
    await tester.pumpWidget(
      await harness.app(
        home: routeLauncher((_) => RoomPage(room: harness.room)),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(RoomPage), findsOneWidget);
    expect(find.byType(MessageTile), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      harness.requests.where(
        (path) => path.contains('read_markers') || path.contains('/event/'),
      ),
      isEmpty,
    );

    await tester.pump(const Duration(milliseconds: 300));
    await harness.settle(tester);

    expect(find.byType(MessageTile), findsOneWidget);
    expect(
      harness.requests.where((path) => path.contains('/event/')),
      hasLength(1),
    );
    expect(
      harness.requests.where((path) => path.contains('read_markers')),
      hasLength(1),
    );
  });

  testWidgets('a slow timeline shows the spinner only after the slide', (
    tester,
  ) async {
    final db = GatedTimelineFakeDatabaseApi();
    final harness = RoomPageHarness(db: db);
    harness.db.events = [harness.message(r'$m1')];
    await tester.pumpWidget(
      await harness.app(
        home: routeLauncher((_) => RoomPage(room: harness.room)),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(MessageTile), findsNothing);

    db.gate.complete();
    await harness.settle(tester);
    expect(find.byType(MessageTile), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
