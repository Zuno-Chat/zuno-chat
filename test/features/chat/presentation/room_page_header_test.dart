import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/features/room_info/presentation/room_info_page.dart';

import '../../../helpers/fake_matrix.dart';
import 'room_page_harness.dart';

void main() {
  late RoomPageHarness harness;

  setUp(() => harness = RoomPageHarness());

  void setJoinRule(String rule) => harness.room.setState(
    buildTestEvent(
      harness.room,
      eventId: r'$join',
      senderId: '@creator:example.org',
      type: EventTypes.RoomJoinRules,
      stateKey: '',
      content: {'join_rule': rule},
    ),
  );

  testWidgets('says Public under the name of a public room', (tester) async {
    setJoinRule('public');
    await harness.pumpRoomPage(tester);

    expect(find.text('Public'), findsOneWidget);
    expect(find.text('Private'), findsNothing);
  });

  testWidgets('tapping the header of a private room opens room info', (
    tester,
  ) async {
    setJoinRule('invite');
    await harness.pumpRoomPage(tester);

    await tester.tap(find.text('Private'));
    await harness.settle(tester);

    expect(find.byType(RoomInfoPage), findsOneWidget);
  });
}
