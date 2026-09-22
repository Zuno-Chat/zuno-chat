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
import 'package:zuno/features/chat/presentation/room_page.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  late Client client;
  late Room room;

  setUp(() {
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    const notificationsChannel = MethodChannel(
      'dexterous.com/flutter/local_notifications',
    );
    const callsChannel = MethodChannel('zuno/calls');
    const recorderChannel = MethodChannel('com.llfbandit.record/messages');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      notificationsChannel,
      (call) async => call.method == 'initialize' ? true : null,
    );
    messenger.setMockMethodCallHandler(callsChannel, (_) async => null);
    messenger.setMockMethodCallHandler(recorderChannel, (_) async => null);
    addTearDown(() {
      messenger.setMockMethodCallHandler(notificationsChannel, null);
      messenger.setMockMethodCallHandler(callsChannel, null);
      messenger.setMockMethodCallHandler(recorderChannel, null);
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

  Future<void> pumpRoomPage(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          scaffoldMessengerKey: globalScaffoldMessengerKey,
          home: RoomPage(room: room),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('the title stays their name and says they left', (tester) async {
    setPartner('leave');
    await pumpRoomPage(tester);

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Left the chat'), findsOneWidget);
    expect(find.textContaining('Empty chat'), findsNothing);
  });

  testWidgets('the composer is replaced by a notice', (tester) async {
    setPartner('leave');
    await pumpRoomPage(tester);

    expect(find.text('Bob left this chat'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('calls cannot be placed', (tester) async {
    setPartner('leave');
    await pumpRoomPage(tester);

    expect(find.byIcon(Icons.call_outlined), findsNothing);
    expect(find.byIcon(Icons.videocam_outlined), findsNothing);
  });

  testWidgets('a live direct chat keeps the composer and calls', (
    tester,
  ) async {
    setPartner('join');
    await pumpRoomPage(tester);

    expect(find.text('Left the chat'), findsNothing);
    expect(find.text('Bob left this chat'), findsNothing);
    expect(find.byType(TextField), findsWidgets);
    expect(find.byIcon(Icons.call_outlined), findsOneWidget);
  });
}
