import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/errors/global_error_handler.dart';
import 'package:zuno/core/matrix/linkified_text.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/chat/presentation/room_page.dart';

import '../../../helpers/fake_matrix.dart';

class _StoredEventsDb extends TimelineCapableFakeDatabaseApi {
  List<Event> Function(Room room) events = (_) => [];

  @override
  Future<List<Event>> getEventList(
    Room room, {
    int start = 0,
    bool onlySending = false,
    int? limit,
  }) async => onlySending || start > 0 ? [] : events(room);
}

void main() {
  late _StoredEventsDb db;
  late Client client;
  late Room room;

  setUp(() {
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

    db = _StoredEventsDb();
    client = Client(
      'test',
      database: db,
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );
    client.setUserId('@me:example.org');
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    room = buildTestRoom(client)..partial = false;
    room.setState(User('@bob:example.org', membership: 'join', room: room));
    client.rooms.add(room);
  });

  Event message(Room room, String id, Map<String, Object?> content) =>
      buildTestEvent(
        room,
        eventId: id,
        senderId: '@bob:example.org',
        content: {'msgtype': 'm.text', ...content},
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
    for (var i = 0; i < 3; i++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('a mention-only formatted body renders as plain text', (
    tester,
  ) async {
    db.events = (room) => [
      message(room, r'$m1', {
        'body': 'hi @Alice',
        'format': 'org.matrix.custom.html',
        'formatted_body':
            'hi <a href="https://matrix.to/#/@alice:example.org">@Alice</a>',
        'm.mentions': {
          'user_ids': ['@alice:example.org'],
        },
      }),
    ];
    await pumpRoomPage(tester);

    expect(find.byType(LinkifiedText), findsOneWidget);
    expect(find.byType(Html), findsNothing);
  });

  testWidgets('real formatting still renders as HTML', (tester) async {
    db.events = (room) => [
      message(room, r'$m2', {
        'body': 'hi there',
        'format': 'org.matrix.custom.html',
        'formatted_body': 'hi <em>there</em>',
      }),
    ];
    await pumpRoomPage(tester);

    expect(find.byType(Html), findsOneWidget);
    expect(find.byType(LinkifiedText), findsNothing);
  });
}
