import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/keep_clear.dart';
import 'package:zuno/features/chat/presentation/message_composer.dart';

import 'room_page_harness.dart';

void main() {
  testWidgets('the floating call window keeps clear of the composer', (
    tester,
  ) async {
    final harness = RoomPageHarness();
    await harness.pumpRoomPage(tester);

    expect(
      find.ancestor(
        of: find.byType(MessageComposer),
        matching: find.byType(KeepClearArea),
      ),
      findsOneWidget,
    );
  });
}
