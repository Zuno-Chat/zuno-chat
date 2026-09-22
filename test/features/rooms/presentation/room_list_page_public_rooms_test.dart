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
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/matrix/room_access.dart';
import 'package:zuno/core/onboarding/onboarding_step.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/chat/presentation/room_page.dart';
import 'package:zuno/features/rooms/presentation/room_list_page.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/public_rooms_fixture.dart';

void main() {
  late Client client;
  late List<http.Request> requests;

  Iterable<http.Request> directoryRequests() =>
      requests.where((r) => r.url.pathSegments.last == 'publicRooms');

  Iterable<http.Request> joinRequests() =>
      requests.where((r) => r.url.pathSegments.contains('join'));

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

    requests = [];
    client = Client(
      'test',
      database: TimelineCapableFakeDatabaseApi(),
      httpClient: MockClient((request) async {
        requests.add(request);
        final segments = request.url.pathSegments;
        if (segments.last == 'publicRooms') {
          final body = request.body.isEmpty
              ? const <String, Object?>{}
              : jsonDecode(request.body) as Map;
          final filter = body['filter'] as Map?;
          final term = filter?['generic_search_term'] as String?;
          return http.Response(publicRoomsFixtureJson(term: term), 200);
        }
        if (segments.contains('join')) {
          return http.Response(jsonEncode({'room_id': segments.last}), 200);
        }
        return http.Response('{}', 200);
      }),
    );
    client.setUserId('@me:example.org');
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
  });

  Future<void> pumpRoomList(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'onboarding.shown.@me:example.org': OnboardingStep.values
          .map((step) => step.name)
          .toList(),
    });
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
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
          home: const RoomListPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  Future<void> openNewChatMenu(WidgetTester tester) async {
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
  }

  Future<void> openPublicRooms(WidgetTester tester) async {
    await openNewChatMenu(tester);
    await tester.tap(find.text('Find public rooms'));
    await settle(tester);
  }

  testWidgets('a new group cannot be named after Zuno', (tester) async {
    await pumpRoomList(tester);
    await openNewChatMenu(tester);
    await tester.tap(find.text('New room'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Zun0 team');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.textContaining('cannot include Zuno'), findsOneWidget);
    expect(
      requests.where((r) => r.url.pathSegments.last == 'createRoom'),
      isEmpty,
    );
  });

  Map<String, Object?> createRoomBody() => jsonDecode(
    requests.singleWhere((r) => r.url.pathSegments.last == 'createRoom').body,
  ) as Map<String, Object?>;

  Future<void> openNewRoomDialog(WidgetTester tester) async {
    await pumpRoomList(tester);
    await openNewChatMenu(tester);
    await tester.tap(find.text('New room'));
    await tester.pumpAndSettle();
  }

  testWidgets('a new room is private unless Public is chosen', (tester) async {
    await openNewRoomDialog(tester);

    expect(
      tester
          .widget<SegmentedButton<RoomAccess>>(
            find.byType(SegmentedButton<RoomAccess>),
          )
          .selected,
      {RoomAccess.private},
    );
    expect(find.text('Invite only'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Book club');
    await tester.tap(find.text('Create'));
    await settle(tester);

    expect(createRoomBody()['preset'], 'private_chat');
    expect(createRoomBody().containsKey('visibility'), isFalse);
  });

  testWidgets('choosing Public says what it means and creates a listed, open '
      'room', (tester) async {
    await openNewRoomDialog(tester);

    await tester.tap(find.text('Public'));
    await tester.pumpAndSettle();
    expect(find.text('Anyone can find and join'), findsOneWidget);
    expect(find.text('Invite only'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Chess club');
    await tester.tap(find.text('Create'));
    await settle(tester);

    expect(createRoomBody()['name'], 'Chess club');
    expect(createRoomBody()['preset'], 'public_chat');
    expect(createRoomBody()['visibility'], 'public');
  });

  testWidgets('cancelling the new room dialog creates nothing', (tester) async {
    await openNewRoomDialog(tester);

    await tester.tap(find.text('Public'));
    await tester.enterText(find.byType(TextField), 'Chess club');
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    expect(
      requests.where((r) => r.url.pathSegments.last == 'createRoom'),
      isEmpty,
    );
  });

  testWidgets('Find public rooms lists the server directory', (tester) async {
    await pumpRoomList(tester);
    await openPublicRooms(tester);

    expect(directoryRequests(), hasLength(1));
    expect(directoryRequests().single.method, 'POST');
    expect(jsonDecode(directoryRequests().single.body)['limit'], 20);
    expect(find.text('Chess club'), findsOneWidget);
    expect(find.text('Gardening'), findsOneWidget);
    expect(find.text('Knitting circle'), findsOneWidget);
    expect(find.text('Hobbies'), findsNothing);
  });

  testWidgets('typing sends the term to the server', (tester) async {
    await pumpRoomList(tester);
    await openPublicRooms(tester);

    await tester.enterText(find.byType(TextField), 'chess');
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);

    final body = jsonDecode(directoryRequests().last.body) as Map;
    expect((body['filter'] as Map)['generic_search_term'], 'chess');
    expect(find.text('Chess club'), findsOneWidget);
    expect(find.text('Gardening'), findsNothing);
  });

  testWidgets('tapping a room asks the server to join it', (tester) async {
    await pumpRoomList(tester);
    await openPublicRooms(tester);

    await tester.tap(find.text('Gardening'));
    await settle(tester);

    expect(joinRequests(), hasLength(1));
    expect(joinRequests().single.url.pathSegments.last, '!garden:example.org');
  });

  testWidgets('a room you already belong to opens without joining', (
    tester,
  ) async {
    client.rooms.add(
      buildTestRoom(client, id: '!chess:example.org')..partial = false,
    );
    await pumpRoomList(tester);
    await openPublicRooms(tester);

    await tester.tap(find.text('Chess club'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(seconds: 1));

    expect(joinRequests(), isEmpty);
    expect(find.byType(RoomPage), findsOneWidget);
  });

  testWidgets('Join room by id is greyed out', (tester) async {
    await pumpRoomList(tester);
    await openNewChatMenu(tester);

    final tile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Join room'),
    );
    expect(tile.enabled, isFalse);
  });
}
