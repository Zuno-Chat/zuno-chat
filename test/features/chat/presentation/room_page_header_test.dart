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
import 'package:zuno/features/room_info/presentation/room_info_page.dart';

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
  });

  void setJoinRule(String rule) => room.setState(
    buildTestEvent(
      room,
      eventId: r'$join',
      senderId: '@creator:example.org',
      type: EventTypes.RoomJoinRules,
      stateKey: '',
      content: {'join_rule': rule},
    ),
  );

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

  testWidgets('says Public under the name of a public room', (tester) async {
    setJoinRule('public');
    await pumpRoomPage(tester);

    expect(find.text('Public'), findsOneWidget);
    expect(find.text('Private'), findsNothing);
  });

  testWidgets('says Private under the name of a private room', (tester) async {
    setJoinRule('invite');
    await pumpRoomPage(tester);

    expect(find.text('Private'), findsOneWidget);
    expect(find.text('Public'), findsNothing);
  });

  testWidgets('tapping the header opens room info', (tester) async {
    setJoinRule('invite');
    await pumpRoomPage(tester);

    await tester.tap(find.text('Private'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(RoomInfoPage), findsOneWidget);
  });
}
