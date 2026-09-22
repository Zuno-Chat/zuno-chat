import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' hide CallSession;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/matrixrtc/call_session.dart';
import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';
import 'package:zuno/core/calls/matrixrtc/incoming_call_provider.dart';
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_provider.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/errors/global_error_handler.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/calls/presentation/incoming_call_page.dart';
import 'package:zuno/features/rooms/presentation/room_list_page.dart';

import '../../../helpers/fake_matrix.dart';

class _SendCapableFakeDatabaseApi extends FakeDatabaseApi {
  @override
  Future<void> transaction(Future<void> Function() action) => action();

  @override
  Future<User?> getUser(String userId, Room room) async => null;

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
}

Map<String, Object?> _inviteContent({
  required String callId,
  CallKind kind = CallKind.voice,
}) => {
  'msgtype': callInviteMsgtype,
  'body': 'Incoming call',
  'call_id': callId,
  'kind': kind.name,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterLocalNotificationsPlatform.instance =
      AndroidFlutterLocalNotificationsPlugin();
  const notificationsChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const callsChannel = MethodChannel('zuno/calls');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Client client;
  late Room room;

  setUp(() {
    ringRateLimiter.clear();
    messenger.setMockMethodCallHandler(
      notificationsChannel,
      (call) async => call.method == 'initialize' ? true : null,
    );
    messenger.setMockMethodCallHandler(callsChannel, (call) async => null);

    client = Client(
      'test',
      database: _SendCapableFakeDatabaseApi(),
      httpClient: MockClient(
        (request) async =>
            http.Response(jsonEncode({'event_id': r'$evt'}), 200),
      ),
    );
    client.setUserId('@me:example.org');
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    room = buildTestRoom(client);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(notificationsChannel, null);
    messenger.setMockMethodCallHandler(callsChannel, null);
  });

  Future<ProviderContainer> pumpRoomList(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matrixClientProvider.overrideWithValue(client),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              scaffoldMessengerKey: globalScaffoldMessengerKey,
              home: const RoomListPage(),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> deliverAndSettle(WidgetTester tester, Event event) async {
    client.onTimelineEvent.add(event);
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  CallSession activeSession({String callId = 'active-call'}) =>
      CallSession.forIncoming(room: room, callId: callId, kind: CallKind.voice);

  testWidgets(
    'a normal incoming call while NOT on a call still rings (regression '
    'guard)',
    (tester) async {
      final container = await pumpRoomList(tester);
      expect(container.read(activeCallProvider), isNull);

      await deliverAndSettle(
        tester,
        buildTestEvent(
          room,
          eventId: r'$invite1',
          senderId: '@bob:example.org',
          content: _inviteContent(callId: 'call1'),
        ),
      );

      expect(find.byType(IncomingCallPage), findsOneWidget);
    },
  );

  testWidgets(
    'a second incoming call while already on one is auto-declined and '
    'never rings',
    (tester) async {
      final container = await pumpRoomList(tester);
      final session = activeSession();
      addTearDown(session.dispose);
      container.read(activeCallProvider.notifier).set(session);

      final declineTxIds = <String?>{};
      client.onTimelineEvent.stream.listen((e) {
        if (e.messageType == callDeclineMsgtype) {
          declineTxIds.add(e.unsigned?.tryGet<String>('transaction_id'));
        }
      });

      await deliverAndSettle(
        tester,
        buildTestEvent(
          room,
          eventId: r'$invite2',
          senderId: '@carol:example.org',
          content: _inviteContent(callId: 'call2'),
        ),
      );

      expect(find.byType(IncomingCallPage), findsNothing);
      expect(declineTxIds, hasLength(1));
      expect(container.read(activeCallProvider), same(session));
      expect(container.read(resolvedCallIdsProvider), contains('call2'));
    },
  );

  testWidgets(
    'two auto-declines back to back for two different second-callers '
    'while still on the original call',
    (tester) async {
      final container = await pumpRoomList(tester);
      final session = activeSession();
      addTearDown(session.dispose);
      container.read(activeCallProvider.notifier).set(session);

      final declineCallIds = <String?>{};
      client.onTimelineEvent.stream.listen((e) {
        if (e.messageType == callDeclineMsgtype) {
          declineCallIds.add(e.content.tryGet<String>('call_id'));
        }
      });

      await deliverAndSettle(
        tester,
        buildTestEvent(
          room,
          eventId: r'$invite2',
          senderId: '@carol:example.org',
          content: _inviteContent(callId: 'call2'),
        ),
      );
      await deliverAndSettle(
        tester,
        buildTestEvent(
          room,
          eventId: r'$invite3',
          senderId: '@dave:example.org',
          content: _inviteContent(callId: 'call3'),
        ),
      );

      expect(find.byType(IncomingCallPage), findsNothing);
      expect(declineCallIds, {'call2', 'call3'});
      expect(container.read(activeCallProvider), same(session));
    },
  );

  testWidgets(
    'a call_id already resolved elsewhere is still ignored, not '
    'auto-declined, even while on another call',
    (tester) async {
      final container = await pumpRoomList(tester);
      final session = activeSession();
      addTearDown(session.dispose);
      container.read(activeCallProvider.notifier).set(session);
      container.read(resolvedCallIdsProvider.notifier).markResolved('call2');

      final declines = <Event>[];
      client.onTimelineEvent.stream.listen((e) {
        if (e.messageType == callDeclineMsgtype) declines.add(e);
      });

      await deliverAndSettle(
        tester,
        buildTestEvent(
          room,
          eventId: r'$invite2',
          senderId: '@carol:example.org',
          content: _inviteContent(callId: 'call2'),
        ),
      );

      expect(find.byType(IncomingCallPage), findsNothing);
      expect(declines, isEmpty);
    },
  );

  testWidgets('the SnackBar actually appears with the right caller info', (
    tester,
  ) async {
    final container = await pumpRoomList(tester);
    final session = activeSession();
    addTearDown(session.dispose);
    container.read(activeCallProvider.notifier).set(session);

    await deliverAndSettle(
      tester,
      buildTestEvent(
        room,
        eventId: r'$invite2',
        senderId: '@carol:example.org',
        content: _inviteContent(callId: 'call2'),
      ),
    );

    expect(find.text('Missed call from Carol'), findsOneWidget);
  });
}
