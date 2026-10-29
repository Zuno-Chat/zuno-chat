import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:zuno/features/chat/presentation/undecryptable_message.dart';

import '../../../helpers/fake_encryption.dart';
import '../../../helpers/fake_http.dart';
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
      httpClient: FakeHttpClient((_) async => http.Response('{}', 200)),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    room = buildTestRoom(client)..partial = false;
    client.rooms.add(room);
  });

  testWidgets('a locked last message turns into the message once its key '
      'opens it', (tester) async {
    room.lastEvent = lockedTestEvent(
      room,
      eventId: r'$enc',
      senderId: '@bob:example.org',
    );
    await pumpRoomListPage(tester, client);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(UndecryptablePreviewText), findsOneWidget);

    room.lastEvent = buildTestEvent(
      room,
      eventId: r'$enc',
      senderId: '@bob:example.org',
      content: {'msgtype': 'm.text', 'body': 'See you at 8'},
    );
    client.onSync.add(
      SyncUpdate(
        nextBatch: '',
        rooms: RoomsUpdate(join: {room.id: JoinedRoomUpdate()}),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(UndecryptablePreviewText), findsNothing);
    expect(find.text('See you at 8'), findsOneWidget);
  });
}
