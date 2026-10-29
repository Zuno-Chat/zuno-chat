import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/errors/global_error_handler.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/currently_open_room_provider.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/matrix/upload_http_client.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/ui/zuno_theme.dart';
import 'package:zuno/features/chat/presentation/room_page.dart';
import 'package:zuno/features/share/presentation/forward_picker_page.dart';

import '../../../helpers/fake_http.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/preferences_container.dart';
import '../../../helpers/room_opening_channels.dart';
import '../../../helpers/route_launcher.dart';

class _AbortHonoringClient extends http.BaseClient {
  _AbortHonoringClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final response = _inner.send(request);
    if (request case http.Abortable(:final abortTrigger?)) {
      return Future.any([
        response,
        abortTrigger.then<http.StreamedResponse>(
          (_) => throw http.RequestAbortedException(request.url),
        ),
      ]);
    }
    return response;
  }
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
  final bool sendsGiveUpAtOnce;
  final Map<String, Object> preferences;
  late final Client client;
  late final Room room;

  RoomPageHarness({
    StoredEventsFakeDatabaseApi? db,
    this.capabilities,
    this.overrides = const [],
    this.encrypting = false,
    this.sendsGiveUpAtOnce = false,
    this.preferences = const {},
  }) : db = db ?? StoredEventsFakeDatabaseApi() {
    installRoomOpeningChannels();

    final httpClient = UploadHttpClient(
      _AbortHonoringClient(
        FakeHttpClient((request) async {
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
            return http.Response('{"event_id":"\$sent${sent.length}"}', 200);
          }
          return notAMemberAnswer(request) ?? http.Response('{}', 200);
        }),
      ),
    );
    client = buildTestClient(
      userId: '@me:example.org',
      database: this.db,
      httpClient: httpClient,
      encrypting: encrypting,
      sendTimelineEventTimeout: sendsGiveUpAtOnce
          ? Duration.zero
          : const Duration(minutes: 1),
    );
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

  void blockPosting() => room.setState(
    buildTestEvent(
      room,
      eventId: r'$pl',
      senderId: '@bob:example.org',
      type: EventTypes.RoomPowerLevels,
      stateKey: '',
      content: {
        'events_default': 50,
        'users': {'@bob:example.org': 100},
      },
    ),
  );

  Event message(String id, {String body = 'hello', DateTime? at}) =>
      buildTestEvent(
        room,
        eventId: id,
        senderId: '@bob:example.org',
        originServerTs: at ?? DateTime(2026, 9, 20, 12),
        status: EventStatus.synced,
        content: {'msgtype': 'm.text', 'body': body},
      );

  void addChat(String id, String name) =>
      client.rooms.add(namedRoom(client, id, name));

  List<Map<String, Object?>> sentTo(String roomId) => [
    for (final request in httpRequests)
      if (request.url.pathSegments.contains(roomId) &&
          request.url.path.contains('/send/m.room.message/'))
        jsonDecode(request.body) as Map<String, Object?>,
  ];

  Future<void> forwardToChats(WidgetTester tester, List<String> chats) async {
    for (final chat in chats) {
      await tester.tap(
        find.descendant(
          of: find.byType(ForwardPickerPage),
          matching: find.text(chat),
        ),
      );
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await settle(tester);
    await drive(tester);
  }

  Future<Widget> app({required Widget home}) async {
    final container = await containerWithPreferences(
      preferences,
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        if (capabilities case final capabilities?)
          platformCapabilitiesProvider.overrideWithValue(capabilities),
        ...overrides,
      ],
    );
    final login = container.listen(isLoggedInProvider.future, (_, _) {});
    await login.read();
    login.close();
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        debugShowCheckedModeBanner: false,
        theme: zunoLightTheme,
        scaffoldMessengerKey: globalScaffoldMessengerKey,
        navigatorObservers: [container.read(openChatObserverProvider)],
        home: home,
      ),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> drive(WidgetTester tester, {int turns = 12}) async {
    for (var i = 0; i < turns; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpRoomPage(WidgetTester tester) async {
    await tester.pumpWidget(await app(home: RoomPage(room: room)));
    await settle(tester);
  }

  Future<void> pumpRoomPageOverLauncher(WidgetTester tester) async {
    await tester.pumpWidget(
      await app(
        home: routeLauncher((_) => RoomPage(room: room), label: 'open chat'),
      ),
    );
    await tester.tap(find.text('open chat'));
    await settle(tester);
  }

  Future<void> openRoomInfo(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Show menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Room info'));
    await settle(tester);
  }
}
