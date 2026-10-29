import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/features/chat/presentation/mention_suggestions.dart';
import 'package:zuno/features/chat/presentation/message_composer.dart';
import 'package:zuno/features/chat/presentation/message_list_view.dart';

import '../../../helpers/fake_matrix.dart';
import 'room_page_harness.dart';

void main() {
  MessageListView list(WidgetTester tester) =>
      tester.widget<MessageListView>(find.byType(MessageListView));

  testWidgets('only a change to this room\'s state rebuilds the page', (
    tester,
  ) async {
    final harness = RoomPageHarness();
    harness.db.events = [harness.message(r'$m1')];
    await harness.pumpRoomPage(tester);
    final before = list(tester);

    harness.client.onSync.add(
      SyncUpdate(
        nextBatch: 's2',
        rooms: RoomsUpdate(
          join: {
            '!other:example.org': JoinedRoomUpdate(
              state: [
                MatrixEvent(
                  eventId: r'$name',
                  type: EventTypes.RoomName,
                  senderId: '@bob:example.org',
                  originServerTs: DateTime(2026, 9, 20),
                  stateKey: '',
                  content: const {'name': 'Elsewhere'},
                ),
              ],
            ),
            harness.room.id: JoinedRoomUpdate(
              summary: RoomSummary.fromJson(const {}),
              timeline: TimelineUpdate(
                events: [
                  MatrixEvent(
                    eventId: r'$m2',
                    type: EventTypes.Message,
                    senderId: '@bob:example.org',
                    originServerTs: DateTime(2026, 9, 20, 12, 1),
                    content: const {'msgtype': 'm.text', 'body': 'later'},
                  ),
                ],
              ),
              ephemeral: [
                BasicEvent(
                  type: 'm.typing',
                  content: const {'user_ids': <String>[]},
                ),
                BasicEvent(type: 'm.receipt', content: const {}),
              ],
            ),
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(identical(list(tester), before), isTrue);

    harness.room.setState(
      buildTestEvent(
        harness.room,
        eventId: r'$topic',
        senderId: '@bob:example.org',
        type: EventTypes.RoomTopic,
        stateKey: '',
        content: {'topic': 'Plans'},
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(identical(list(tester), before), isFalse);
  });

  testWidgets('a room turning direct rebuilds the page', (tester) async {
    final harness = RoomPageHarness();
    harness.db.events = [harness.message(r'$m1')];
    await harness.pumpRoomPage(tester);
    expect(find.byType(MentionSuggestions), findsOneWidget);

    final direct = BasicEvent(
      type: 'm.direct',
      content: {
        '@bob:example.org': [harness.room.id],
      },
    );
    harness.client.accountData[direct.type] = direct;
    harness.client.onSync.add(
      SyncUpdate(nextBatch: 's2', accountData: [direct]),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(MentionSuggestions), findsNothing);
  });

  testWidgets('a recording tick does not rebuild the list', (tester) async {
    final harness = RoomPageHarness();
    harness.db.events = [harness.message(r'$m1')];
    await harness.pumpRoomPage(tester);
    final before = list(tester);

    final composer = tester.widget<MessageComposer>(
      find.byType(MessageComposer),
    );
    (composer.recorder.elapsed as ValueNotifier<Duration>).value =
        const Duration(seconds: 3);
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
    await tester.pump(kDoubleTapMinTime);

    expect(find.byTooltip('Scroll to latest'), findsOneWidget);
    expect(identical(list(tester), before), isTrue);
  });
}
