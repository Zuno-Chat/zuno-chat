import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/errors/global_error_handler.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/rooms/presentation/room_list_page.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late Room room;

  setUp(() {
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    const notificationsChannel = MethodChannel(
      'dexterous.com/flutter/local_notifications',
    );
    const callsChannel = MethodChannel('zuno/calls');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      notificationsChannel,
      (call) async => call.method == 'initialize' ? true : null,
    );
    messenger.setMockMethodCallHandler(callsChannel, (_) async => null);
    addTearDown(() {
      messenger.setMockMethodCallHandler(notificationsChannel, null);
      messenger.setMockMethodCallHandler(callsChannel, null);
    });

    client = Client(
      'test',
      database: TimelineCapableFakeDatabaseApi(),
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );
    client.setUserId('@me:example.org');
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
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matrixClientProvider.overrideWithValue(client),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          scaffoldMessengerKey: globalScaffoldMessengerKey,
          home: const RoomListPage(),
        ),
      ),
    );
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
