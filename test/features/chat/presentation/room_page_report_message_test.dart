import 'dart:convert';

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
  late List<http.Request> requests;
  late bool refuseReports;

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
    requests = [];
    refuseReports = false;
    client = Client(
      'test',
      database: db,
      httpClient: MockClient((request) async {
        requests.add(request);
        if (refuseReports && request.url.path.contains('/report/')) {
          return http.Response(
            jsonEncode({'errcode': 'M_LIMIT_EXCEEDED', 'error': 'Slow down'}),
            429,
          );
        }
        return http.Response('{}', 200);
      }),
    );
    client.setUserId('@me:example.org');
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    room = buildTestRoom(client)..partial = false;
    room.setState(User('@bob:example.org', membership: 'join', room: room));
    room.setState(User('@me:example.org', membership: 'join', room: room));
    client.rooms.add(room);
  });

  Event message(Room room, String id, {required String from}) => buildTestEvent(
    room,
    eventId: id,
    senderId: from,
    content: {'msgtype': 'm.text', 'body': 'the private words'},
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

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> openActions(WidgetTester tester) async {
    await tester.longPress(find.byType(LinkifiedText));
    await settle(tester);
  }

  Iterable<http.Request> reports() =>
      requests.where((r) => r.url.path.contains('/report/'));

  testWidgets('reports a message from someone else without its content', (
    tester,
  ) async {
    db.events = (room) => [message(room, r'$bad', from: '@bob:example.org')];
    await pumpRoomPage(tester);

    await openActions(tester);
    await tester.tap(find.text('Report'));
    await settle(tester);
    expect(find.text('Report message'), findsOneWidget);
    await tester.tap(find.text('Spam'));
    await tester.pump();
    await tester.tap(find.text('Send report'));
    await settle(tester);

    expect(reports(), hasLength(1));
    expect(
      reports().single.url.path,
      '/_matrix/client/v3/rooms/${Uri.encodeComponent(room.id)}'
      '/report/${Uri.encodeComponent(r'$bad')}',
    );
    expect(jsonDecode(reports().single.body), {'reason': 'spam'});
    expect(find.text('Report sent'), findsOneWidget);
  });

  testWidgets('your own message cannot be reported', (tester) async {
    db.events = (room) => [message(room, r'$mine', from: '@me:example.org')];
    await pumpRoomPage(tester);

    await openActions(tester);

    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Report'), findsNothing);
  });

  testWidgets('a refused report stays open and confirms nothing', (
    tester,
  ) async {
    refuseReports = true;
    db.events = (room) => [message(room, r'$bad', from: '@bob:example.org')];
    await pumpRoomPage(tester);

    await openActions(tester);
    await tester.tap(find.text('Report'));
    await settle(tester);
    await tester.tap(find.text('Spam'));
    await tester.pump();
    await tester.tap(find.text('Send report'));
    await settle(tester);

    expect(find.text('The report was not sent. Try again.'), findsOneWidget);
    expect(find.text('Report sent'), findsNothing);
  });
}
