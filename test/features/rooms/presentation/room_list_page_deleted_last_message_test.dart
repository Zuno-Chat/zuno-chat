import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/room_list_page_harness.dart';
import '../../../helpers/room_opening_channels.dart';

void main() {
  late Client client;
  late Room room;

  setUp(() {
    installRoomOpeningChannels();
    client = buildTestClient(
      userId: '@me:example.org',
      database: TimelineCapableFakeDatabaseApi(),
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    room = buildTestRoom(client)..partial = false;
    client.rooms.add(room);
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        '@bob:example.org': [room.id],
      },
    );
  });

  Event message() => buildTestEvent(
    room,
    eventId: r'$msg',
    senderId: '@me:example.org',
    content: {'msgtype': 'm.text', 'body': 'Secret plan'},
  );

  Event redactionOf(String eventId) => buildTestEvent(
    room,
    eventId: r'$redaction',
    senderId: '@me:example.org',
    type: EventTypes.Redaction,
    content: {'redacts': eventId},
  );

  Future<void> pumpRoomList(WidgetTester tester) async {
    await pumpRoomListPage(tester, client);
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> sync(WidgetTester tester) async {
    client.onSync.add(SyncUpdate(nextBatch: 'next'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('a deleted last message stops showing its text', (tester) async {
    room.lastEvent = message();
    await pumpRoomList(tester);
    expect(find.text('Secret plan'), findsOneWidget);

    room.lastEvent!.setRedactionEvent(redactionOf(r'$msg'));
    await sync(tester);

    expect(find.text('Secret plan'), findsNothing);
    expect(find.text('Message deleted'), findsOneWidget);
  });

  testWidgets(
    'a deleted last message stops showing its text after the synced copy '
    'replaced the sent one',
    (tester) async {
      room.lastEvent = message();
      await pumpRoomList(tester);

      room.lastEvent = message();
      await sync(tester);
      expect(find.text('Secret plan'), findsOneWidget);

      room.lastEvent!.setRedactionEvent(redactionOf(r'$msg'));
      await sync(tester);

      expect(find.text('Secret plan'), findsNothing);
      expect(find.text('Message deleted'), findsOneWidget);
    },
  );

  testWidgets('a new message after a deleted one takes over the preview', (
    tester,
  ) async {
    room.lastEvent = message();
    await pumpRoomList(tester);

    room.lastEvent!.setRedactionEvent(redactionOf(r'$msg'));
    await sync(tester);
    room.lastEvent = buildTestEvent(
      room,
      eventId: r'$next',
      senderId: '@bob:example.org',
      content: {'msgtype': 'm.text', 'body': 'Fresh start'},
    );
    await sync(tester);

    expect(find.text('Message deleted'), findsNothing);
    expect(find.text('Fresh start'), findsOneWidget);
  });
}
