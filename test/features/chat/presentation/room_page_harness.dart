import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/errors/global_error_handler.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/matrix/upload_progress_http_client.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/chat/presentation/room_page.dart';

import '../../../helpers/fake_matrix.dart';
import '../../../helpers/preferences_container.dart';
import '../../../helpers/room_opening_channels.dart';

class SendingFakeDatabaseApi extends StoredEventsFakeDatabaseApi
    with SendCapableDatabase, MediaCapableDatabase {
  final deletedTimelines = <String>[];
  Object? deleteTimelineError;

  @override
  Future<void> removeEvent(String eventId, String roomId) async {}

  @override
  Future<void> storeFile(Uri mxcUri, Uint8List bytes, int time) async {}

  @override
  Future<bool> deleteFile(Uri mxcUri) async => true;

  @override
  Future<void> deleteTimelineForRoom(String roomId) async {
    final error = deleteTimelineError;
    if (error != null) throw error;
    deletedTimelines.add(roomId);
  }
}

class _HarnessClient extends Client {
  _HarnessClient(
    super.clientName, {
    required super.database,
    required super.httpClient,
    required this.encrypting,
  });

  final bool encrypting;

  @override
  bool get encryptionEnabled => encrypting || super.encryptionEnabled;
}

class RoomPageHarness {
  final StoredEventsFakeDatabaseApi db;
  final requests = <String>[];
  final httpRequests = <http.Request>[];
  final sent = <Map<String, Object?>>[];
  FutureOr<http.Response?> Function(http.Request request)? respond;
  final PlatformCapabilities? capabilities;
  final List<Override> overrides;
  final bool encrypting;
  late final Client client;
  late final Room room;
  late final UploadProgressHttpClient httpClient;

  RoomPageHarness({
    StoredEventsFakeDatabaseApi? db,
    this.capabilities,
    this.overrides = const [],
    this.encrypting = false,
  }) : db = db ?? StoredEventsFakeDatabaseApi() {
    installRoomOpeningChannels();

    httpClient = UploadProgressHttpClient(
      MockClient((request) async {
        requests.add(request.url.path);
        httpRequests.add(request);
        final custom = await respond?.call(request);
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
    client = _HarnessClient(
      'test',
      database: this.db,
      httpClient: httpClient,
      encrypting: encrypting,
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
    final container = await containerWithPreferences(
      {},
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        uploadProgressHttpClientProvider.overrideWithValue(httpClient),
        if (capabilities case final capabilities?)
          platformCapabilitiesProvider.overrideWithValue(capabilities),
        ...overrides,
      ],
    );
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
