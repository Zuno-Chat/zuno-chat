import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/errors/global_error_handler.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/matrix/upload_progress_http_client.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/chat/presentation/room_page.dart';

import '../../../helpers/fake_matrix.dart';

class SendingFakeDatabaseApi extends StoredEventsFakeDatabaseApi {
  final deletedTimelines = <String>[];
  Object? deleteTimelineError;

  @override
  int get maxFileSize => 0;

  @override
  Future<void> storeEventUpdate(
    String roomId,
    StrippedStateEvent event,
    EventUpdateType type,
    Client client,
  ) async {}

  @override
  Future<void> storeRoomUpdate(
    String roomId,
    SyncRoomUpdate roomUpdate,
    Event? lastEvent,
    Client client,
  ) async {}

  @override
  Future<void> removeEvent(String eventId, String roomId) async {}

  @override
  Future<void> storeFile(Uri mxcUri, Uint8List bytes, int time) async {}

  @override
  Future<bool> deleteFile(Uri mxcUri) async => true;

  @override
  Future<({Map<String, Object?> content, DateTime savedAt})?>
  getCustomCacheObject(String cacheKey) async => null;

  @override
  Future<void> cacheCustomObject(
    String cacheKey,
    Map<String, Object?> content,
  ) async {}

  @override
  Future<void> deleteTimelineForRoom(String roomId) async {
    final error = deleteTimelineError;
    if (error != null) throw error;
    deletedTimelines.add(roomId);
  }
}

class RoomPageHarness {
  final StoredEventsFakeDatabaseApi db;
  final requests = <String>[];
  final httpRequests = <http.Request>[];
  final sent = <Map<String, Object?>>[];
  http.Response? Function(http.Request request)? respond;
  final PlatformCapabilities? capabilities;
  final List<Override> overrides;
  late final Client client;
  late final Room room;
  late final UploadProgressHttpClient httpClient;

  RoomPageHarness({
    StoredEventsFakeDatabaseApi? db,
    this.capabilities,
    this.overrides = const [],
  }) : db = db ?? StoredEventsFakeDatabaseApi() {
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

    httpClient = UploadProgressHttpClient(
      MockClient((request) async {
        requests.add(request.url.path);
        httpRequests.add(request);
        final custom = respond?.call(request);
        if (custom != null) return custom;
        if (request.url.path.endsWith('/versions')) {
          return http.Response(
            jsonEncode({
              'versions': ['v1.11'],
            }),
            200,
          );
        }
        if (request.url.path.contains('/send/m.room.message/')) {
          sent.add(jsonDecode(request.body) as Map<String, Object?>);
          return http.Response('{"event_id":"\$sent"}', 200);
        }
        return http.Response('{}', 200);
      }),
    );
    client = Client('test', database: this.db, httpClient: httpClient);
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
        uploadProgressHttpClientProvider.overrideWithValue(httpClient),
        sharedPreferencesProvider.overrideWithValue(prefs),
        if (capabilities case final capabilities?)
          platformCapabilitiesProvider.overrideWithValue(capabilities),
        ...overrides,
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

  Future<void> drive(WidgetTester tester, {int turns = 12}) async {
    for (var i = 0; i < turns; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
  }

  Future<void> pumpRoomPage(WidgetTester tester) async {
    await tester.pumpWidget(await app(home: RoomPage(room: room)));
    await settle(tester);
  }
}
