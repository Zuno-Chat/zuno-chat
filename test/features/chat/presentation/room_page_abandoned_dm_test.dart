import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import '../../../helpers/fake_matrix.dart';
import 'room_page_harness.dart';

void main() {
  late RoomPageHarness harness;

  setUp(() {
    harness = RoomPageHarness();
    harness.client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        '@bob:example.org': [harness.room.id],
      },
    );
  });

  void setPartner(String membership) {
    final room = harness.room;
    room.setState(
      buildTestEvent(
        room,
        eventId: '\$bob-$membership',
        senderId: '@bob:example.org',
        type: EventTypes.RoomMember,
        stateKey: '@bob:example.org',
        content: {'membership': membership, 'displayname': 'Bob'},
      ),
    );
    room.summary.mJoinedMemberCount = membership == 'join' ? 2 : 1;
    room.summary.mInvitedMemberCount = 0;
  }

  testWidgets('the title stays their name and says they left', (tester) async {
    setPartner('leave');
    await harness.pumpRoomPage(tester);

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Left the chat'), findsOneWidget);
    expect(find.textContaining('Empty chat'), findsNothing);
  });

  testWidgets('the composer is replaced by a notice', (tester) async {
    setPartner('leave');
    await harness.pumpRoomPage(tester);

    expect(find.text('Bob left this chat'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('calls cannot be placed', (tester) async {
    setPartner('leave');
    await harness.pumpRoomPage(tester);

    expect(find.byIcon(Icons.call_outlined), findsNothing);
    expect(find.byIcon(Icons.videocam_outlined), findsNothing);
  });

  testWidgets('a live direct chat keeps the composer and calls', (
    tester,
  ) async {
    setPartner('join');
    await harness.pumpRoomPage(tester);

    expect(find.text('Left the chat'), findsNothing);
    expect(find.text('Bob left this chat'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.call_outlined), findsOneWidget);
  });
}
