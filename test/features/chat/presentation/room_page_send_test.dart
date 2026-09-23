import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/features/chat/presentation/send_icon.dart';

import '../../../helpers/fake_matrix.dart';
import 'room_page_harness.dart';

class _SendCapableFakeDatabaseApi extends StoredEventsFakeDatabaseApi {
  @override
  Future<void> storeEventUpdate(
    String roomId,
    StrippedStateEvent event,
    EventUpdateType type,
    Client client,
  ) async {}

  @override
  Future<void> storeRoomUpdate(
    String roomId,
    SyncRoomUpdate roomUpdate,
    Event? lastEvent,
    Client client,
  ) async {}
}

void main() {
  setUp(rootBundle.clear);

  Future<List<Map<String, Object?>>> send(
    WidgetTester tester,
    String text,
  ) async {
    final harness = RoomPageHarness(db: _SendCapableFakeDatabaseApi());
    await harness.pumpRoomPage(tester);
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.tap(find.byType(SendIcon));
    await harness.settle(tester);
    return harness.sent;
  }

  testWidgets('markdown characters are sent as typed', (tester) async {
    final sent = await send(tester, '**bold** and `code`');

    expect(sent.single['body'], '**bold** and `code`');
    expect(sent.single.containsKey('formatted_body'), isFalse);
  });

  testWidgets('a leading slash is sent as text', (tester) async {
    final sent = await send(tester, '/me waves');

    expect(sent.single['msgtype'], MessageTypes.Text);
    expect(sent.single['body'], '/me waves');
  });

  testWidgets('a mention still notifies without a formatted body', (
    tester,
  ) async {
    final sent = await send(tester, 'hi @bob:example.org');

    expect(sent.single['m.mentions'], {
      'user_ids': ['@bob:example.org'],
    });
    expect(sent.single.containsKey('formatted_body'), isFalse);
  });
}
