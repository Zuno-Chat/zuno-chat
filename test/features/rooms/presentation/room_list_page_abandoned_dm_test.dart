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
import 'package:zuno/features/rooms/presentation/chat_row.dart';
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

  void setPartner(String membership) {
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

  void setLastMessage() {
    room.lastEvent = buildTestEvent(
      room,
      eventId: r'$msg',
      senderId: '@bob:example.org',
      content: {'msgtype': 'm.text', 'body': 'Sure, talk soon'},
    );
  }

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

  Color? nameColor(WidgetTester tester) =>
      tester.widget<Text>(find.text('Bob')).style?.color;

  ColorScheme scheme(WidgetTester tester) =>
      Theme.of(tester.element(find.text('Bob'))).colorScheme;

  testWidgets('the status replaces the last message', (tester) async {
    setPartner('leave');
    setLastMessage();
    await pumpRoomList(tester);

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Left the chat'), findsOneWidget);
    expect(find.text('Sure, talk soon'), findsNothing);
  });

  testWidgets('the tile recedes and is marked', (tester) async {
    setPartner('leave');
    setLastMessage();
    await pumpRoomList(tester);

    expect(nameColor(tester), scheme(tester).onSurfaceVariant);
    expect(
      find.ancestor(of: find.text('Bob'), matching: find.byType(Opacity)),
      findsNothing,
    );
    expect(find.byIcon(Icons.person_off_outlined), findsOneWidget);
  });

  testWidgets('the chat can still be opened', (tester) async {
    setPartner('leave');
    setLastMessage();
    await pumpRoomList(tester);

    final row = tester.widget<ChatRow>(find.byType(ChatRow).first);
    expect(row.onTap, isNotNull);
  });

  testWidgets('a live direct chat is untouched', (tester) async {
    setPartner('join');
    setLastMessage();
    await pumpRoomList(tester);

    expect(find.text('Sure, talk soon'), findsOneWidget);
    expect(find.text('Left the chat'), findsNothing);
    expect(find.byIcon(Icons.person_off_outlined), findsNothing);
    expect(nameColor(tester), scheme(tester).onSurface);
  });
}
