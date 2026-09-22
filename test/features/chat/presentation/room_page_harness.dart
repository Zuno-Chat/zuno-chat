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
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/chat/presentation/room_page.dart';

import '../../../helpers/fake_matrix.dart';

class RoomPageHarness {
  final StoredEventsFakeDatabaseApi db;
  final requests = <String>[];
  late final Client client;
  late final Room room;

  RoomPageHarness({StoredEventsFakeDatabaseApi? db})
    : db = db ?? StoredEventsFakeDatabaseApi() {
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final channels = [
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      const MethodChannel('zuno/calls'),
      const MethodChannel('com.llfbandit.record/messages'),
    ];
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'initialize' ? true : null,
      );
    }
    addTearDown(() {
      for (final channel in channels) {
        messenger.setMockMethodCallHandler(channel, null);
      }
    });

    client = Client(
      'test',
      database: this.db,
      httpClient: MockClient((request) async {
        requests.add(request.url.path);
        return http.Response('{}', 200);
      }),
    );
    client.setUserId('@me:example.org');
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    room = buildTestRoom(client)..partial = false;
    room.setState(
      User(
        '@bob:example.org',
        membership: 'join',
        displayName: 'Bob',
        room: room,
      ),
    );
    room.setState(
      User(
        '@me:example.org',
        membership: 'join',
        displayName: 'Me',
        room: room,
      ),
    );
    client.rooms.add(room);
  }

  Event message(String id, {String body = 'hello', DateTime? at}) =>
      buildTestEvent(
        room,
        eventId: id,
        senderId: '@bob:example.org',
        originServerTs: at ?? DateTime(2026, 9, 20, 12),
        status: EventStatus.synced,
        content: {'msgtype': 'm.text', 'body': body},
      );

  Future<Widget> app({required Widget home}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: zunoLightTheme,
        scaffoldMessengerKey: globalScaffoldMessengerKey,
        home: home,
      ),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> pumpRoomPage(WidgetTester tester) async {
    await tester.pumpWidget(await app(home: RoomPage(room: room)));
    await settle(tester);
  }
}
