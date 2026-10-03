import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
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
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_store.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/calls/notifications/ringing_call_store.dart';
import 'package:zuno/core/calls/platform/incoming_call_presenter.dart';
import 'package:zuno/core/calls/platform/system_ring.dart';
import 'package:zuno/core/errors/global_error_handler.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/calls/presentation/incoming_call_page.dart';
import 'package:zuno/features/rooms/presentation/room_list_page.dart';

import '../../../helpers/call_membership.dart';
import '../../../helpers/fake_call_style_channel.dart';
import '../../../helpers/fake_calls_channel.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/platform_capabilities.dart';

class _PendingRingPresenter implements IncomingCallPresenter {
  final shownCallIds = <String>[];

  @override
  Future<RingOutcome> showIncoming({
    required String callerName,
    required String callerId,
    required bool isVideo,
    required String roomId,
    required String callId,
    bool isGroupCall = false,
    String? roomName,
    Uint8List? avatarBytes,
    Future<RingingCallInfo?>? ringingNow,
  }) {
    shownCallIds.add(callId);
    return Completer<RingOutcome>().future;
  }

  @override
  Future<void> cancelIncoming({
    String? roomId,
    String? callId,
    RingEnd end = RingEnd.remoteEnded,
  }) async {}

  @override
  Future<RingingCallInfo?> activeRing() async => null;
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
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Client client;
  late Room room;
  late RecordedCallsChannel native;
  Object? ringReply;

  setUp(() {
    ringRateLimiter.clear();
    ringReply = null;
    messenger.setMockMethodCallHandler(
      notificationsChannel,
      (call) async => call.method == 'initialize' ? true : null,
    );
    native = installFakeCallsChannel(
      reply: (call) => call.method == 'reportIncomingCall' ? ringReply : null,
    );

    client = buildTestClient(
      userId: '@me:example.org',
      deviceId: 'THISPHONE',
      database: SendCapableFakeDatabaseApi(),
      httpClient: MockClient(
        (request) async =>
            http.Response(jsonEncode({'event_id': r'$evt'}), 200),
      ),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    room = buildTestRoom(client);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(notificationsChannel, null);
  });

  Future<ProviderContainer> pumpRoomList(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matrixClientProvider.overrideWithValue(client),
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...overrides,
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

  Future<({ProviderContainer container, _PendingRingPresenter presenter})>
  pumpWithPendingRings(WidgetTester tester) async {
    final presenter = _PendingRingPresenter();
    final container = await pumpRoomList(
      tester,
      overrides: [incomingCallPresenterProvider.overrideWithValue(presenter)],
    );
    return (container: container, presenter: presenter);
  }

  Future<void> deliverAndSettle(WidgetTester tester, Event event) async {
    client.onTimelineEvent.add(event);
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  CallSession activeSession({String callId = 'active-call'}) =>
      CallSession.forIncoming(room: room, callId: callId, kind: CallKind.voice);

  Event invite({
    required String callId,
    String senderId = '@bob:example.org',
    CallKind kind = CallKind.voice,
  }) => buildTestEvent(
    room,
    eventId: '\$invite-$callId',
    senderId: senderId,
    content: _inviteContent(callId: callId, kind: kind),
  );

  Set<String?> declinedCallIds() {
    final declined = <String?>{};
    client.onTimelineEvent.stream.listen((e) {
      if (e.messageType == callDeclineMsgtype) {
        declined.add(e.content.tryGet<String>('call_id'));
      }
    });
    return declined;
  }

  List<String> ringScreenCallIds(WidgetTester tester) => [
    for (final page in tester.widgetList<IncomingCallPage>(
      find.byType(IncomingCallPage, skipOffstage: false),
    ))
      page.call.callId,
  ];

  Future<void> declineOnRingScreen(WidgetTester tester) async {
    final decline = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.call_end),
    );
    await tester.runAsync(() => decline.onPressed!.call() as Future<void>);
    await tester.pumpAndSettle();
  }

  Event hangUp({required String callId}) => buildTestEvent(
    room,
    eventId: '\$summary-$callId',
    senderId: '@bob:example.org',
    content: CallSummary(
      callId: callId,
      kind: 'voice',
      status: CallSummaryStatus.missed,
      durationMs: 0,
    ).toMessageContent(),
  );

  void answerOnMyOtherDevice(String callId) => joinCall(
    room,
    userId: '@me:example.org',
    deviceId: 'LAPTOP',
    callId: callId,
  );

  void nameRoom(String name) => room.setState(
    StrippedStateEvent(
      type: EventTypes.RoomName,
      senderId: '@me:example.org',
      stateKey: '',
      content: {'name': name},
    ),
  );

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

  testWidgets('two auto-declines back to back for two different second-callers '
      'while still on the original call', (tester) async {
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
  });

  testWidgets('a call another isolate already ended never rings from sync, '
      'though this isolate\'s memory missed it', (tester) async {
    final (:presenter, container: _) = await pumpWithPendingRings(tester);
    await markCallResolvedOnDisk(
      await SharedPreferences.getInstance(),
      'call1',
    );
    final declined = declinedCallIds();

    await deliverAndSettle(tester, invite(callId: 'call1'));

    expect(presenter.shownCallIds, isEmpty);
    expect(ringScreenCallIds(tester), isEmpty);
    expect(declined, isEmpty);
    expect(SystemRing.instance.ringing.value, isNull);
  });

  testWidgets('a call_id already resolved elsewhere is still ignored, not '
      'auto-declined, even while on another call', (tester) async {
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
  });

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

  testWidgets('a call my other device already answered is neither declined '
      'as busy nor announced as missed while on another call', (tester) async {
    final container = await pumpRoomList(tester);
    final session = activeSession();
    addTearDown(session.dispose);
    container.read(activeCallProvider.notifier).set(session);
    answerOnMyOtherDevice('call2');
    final declined = declinedCallIds();

    await deliverAndSettle(
      tester,
      invite(callId: 'call2', senderId: '@carol:example.org'),
    );

    expect(declined, isEmpty);
    expect(find.textContaining('Missed call'), findsNothing);
    expect(container.read(resolvedCallIdsProvider), contains('call2'));
    expect(container.read(activeCallProvider), same(session));
  });

  testWidgets('with VoIP rings on iOS the room list leaves an invite to the '
      'ring coordinator', (tester) async {
    ambientCapabilities = capabilitiesLike(iosCapabilities, voipRing: true);
    ringReply = 'shown';
    await pumpRoomList(tester);

    await deliverAndSettle(tester, invite(callId: 'call1'));

    expect(native.argsOf('reportIncomingCall'), isEmpty);
    expect(find.byType(IncomingCallPage), findsNothing);
    expect(SystemRing.instance.ringing.value, isNull);
  });

  group('ios without VoIP rings', () {
    setUp(
      () => ambientCapabilities = capabilitiesLike(
        iosCapabilities,
        voipRing: false,
      ),
    );

    testWidgets('a ring the system shows opens no ring screen of its own', (
      tester,
    ) async {
      ringReply = 'shown';
      nameRoom('Weekend hike');
      await pumpRoomList(tester);
      final declined = declinedCallIds();

      await deliverAndSettle(
        tester,
        invite(callId: 'call1', kind: CallKind.video),
      );

      expect(find.byType(IncomingCallPage), findsNothing);
      expect(native.argsOf('reportIncomingCall'), [
        {
          'roomId': room.id,
          'callId': 'call1',
          'callerId': '@bob:example.org',
          'name': 'Weekend hike',
          'isVideo': true,
        },
      ]);
      expect(SystemRing.instance.ringing.value, (
        roomId: room.id,
        callId: 'call1',
      ));
      expect(declined, isEmpty);
      SystemRing.instance.clear('call1');
    });

    testWidgets('a ring the system cannot show falls back to the ring screen', (
      tester,
    ) async {
      ringReply = null;
      await pumpRoomList(tester);

      await deliverAndSettle(tester, invite(callId: 'call1'));

      expect(native.argsOf('reportIncomingCall'), hasLength(1));
      expect(find.byType(IncomingCallPage), findsOneWidget);
      expect(SystemRing.instance.ringing.value, isNull);
    });

    testWidgets('a ring the system filtered out shows nothing and declines '
        'nothing', (tester) async {
      ringReply = 'filtered';
      await pumpRoomList(tester);
      final declined = declinedCallIds();

      await deliverAndSettle(tester, invite(callId: 'call1'));

      expect(native.argsOf('reportIncomingCall'), hasLength(1));
      expect(find.byType(IncomingCallPage), findsNothing);
      expect(SystemRing.instance.ringing.value, isNull);
      expect(declined, isEmpty);
    });

    testWidgets('a second call while another is ringing is declined like '
        'call waiting and never reaches the system', (tester) async {
      ringReply = 'shown';
      final container = await pumpRoomList(tester);
      SystemRing.instance.set(roomId: room.id, callId: 'ringing-call');
      final declined = declinedCallIds();

      await deliverAndSettle(
        tester,
        invite(callId: 'call2', senderId: '@carol:example.org'),
      );

      expect(find.byType(IncomingCallPage), findsNothing);
      expect(declined, {'call2'});
      expect(container.read(resolvedCallIdsProvider), contains('call2'));
      expect(find.text('Missed call from Carol'), findsOneWidget);
      expect(native.argsOf('reportIncomingCall'), isEmpty);
      expect(SystemRing.instance.ringing.value?.callId, 'ringing-call');
      SystemRing.instance.clear('ringing-call');
    });

    testWidgets('the invite for the call already ringing is not declined, it '
        'goes to the system', (tester) async {
      ringReply = 'shown';
      final container = await pumpRoomList(tester);
      SystemRing.instance.set(roomId: room.id, callId: 'call1');
      final declined = declinedCallIds();

      await deliverAndSettle(tester, invite(callId: 'call1'));

      expect(declined, isEmpty);
      expect(container.read(resolvedCallIdsProvider), isNot(contains('call1')));
      expect(find.textContaining('Missed call'), findsNothing);
      expect(
        native.argsOf('reportIncomingCall').map((a) => (a! as Map)['callId']),
        ['call1'],
      );
      expect(find.byType(IncomingCallPage), findsNothing);
      SystemRing.instance.clear('call1');
    });

    testWidgets('a call my other device already answered is not declined as '
        'busy while another call rings', (tester) async {
      ringReply = 'shown';
      final container = await pumpRoomList(tester);
      SystemRing.instance.set(roomId: room.id, callId: 'ringing-call');
      answerOnMyOtherDevice('call2');
      final declined = declinedCallIds();

      await deliverAndSettle(
        tester,
        invite(callId: 'call2', senderId: '@carol:example.org'),
      );

      expect(declined, isEmpty);
      expect(find.textContaining('Missed call'), findsNothing);
      expect(container.read(resolvedCallIdsProvider), contains('call2'));
      expect(native.argsOf('reportIncomingCall'), isEmpty);
      expect(SystemRing.instance.ringing.value?.callId, 'ringing-call');
      SystemRing.instance.clear('ringing-call');
    });

    testWidgets('a call my other device already answered never reaches the '
        'system', (tester) async {
      ringReply = 'shown';
      final container = await pumpRoomList(tester);
      answerOnMyOtherDevice('call1');
      final declined = declinedCallIds();

      await deliverAndSettle(tester, invite(callId: 'call1'));

      expect(native.argsOf('reportIncomingCall'), isEmpty);
      expect(native.argsOf('endIncomingCall'), [
        {'roomId': room.id, 'callId': 'call1', 'reason': 'answeredElsewhere'},
      ]);
      expect(find.byType(IncomingCallPage), findsNothing);
      expect(container.read(resolvedCallIdsProvider), contains('call1'));
      expect(declined, isEmpty);
      expect(SystemRing.instance.ringing.value, isNull);
    });
  });

  group('android', () {
    setUp(() => ambientCapabilities = androidCapabilities);

    testWidgets('the ring screen opens at once, without waiting on the ring '
        'notification', (tester) async {
      final (:presenter, container: _) = await pumpWithPendingRings(tester);

      await deliverAndSettle(tester, invite(callId: 'call1'));

      expect(presenter.shownCallIds, ['call1']);
      expect(find.byType(IncomingCallPage), findsOneWidget);
      expect(native.argsOf('reportIncomingCall'), isEmpty);
    });

    testWidgets('a ringing call holds the system ring until its ring screen '
        'goes away', (tester) async {
      await pumpWithPendingRings(tester);

      await deliverAndSettle(tester, invite(callId: 'call1'));

      expect(ringScreenCallIds(tester), ['call1']);
      expect(SystemRing.instance.ringing.value, (
        roomId: room.id,
        callId: 'call1',
      ));

      await deliverAndSettle(tester, hangUp(callId: 'call1'));

      expect(ringScreenCallIds(tester), isEmpty);
      expect(SystemRing.instance.ringing.value, isNull);
    });

    testWidgets('a second call while another is ringing is declined like '
        'call waiting and never rings', (tester) async {
      final (:container, :presenter) = await pumpWithPendingRings(tester);
      await deliverAndSettle(tester, invite(callId: 'call1'));
      final declined = declinedCallIds();

      await deliverAndSettle(
        tester,
        invite(callId: 'call2', senderId: '@carol:example.org'),
      );

      expect(declined, {'call2'});
      expect(container.read(resolvedCallIdsProvider), contains('call2'));
      expect(find.text('Missed call from Carol'), findsOneWidget);
      expect(ringScreenCallIds(tester), ['call1']);
      expect(presenter.shownCallIds, ['call1']);
      expect(SystemRing.instance.ringing.value?.callId, 'call1');
    });

    testWidgets('the invite for the call already ringing is not declined, it '
        'rings', (tester) async {
      final (:container, :presenter) = await pumpWithPendingRings(tester);
      SystemRing.instance.set(roomId: room.id, callId: 'call1');
      final declined = declinedCallIds();

      await deliverAndSettle(tester, invite(callId: 'call1'));

      expect(declined, isEmpty);
      expect(container.read(resolvedCallIdsProvider), isNot(contains('call1')));
      expect(find.textContaining('Missed call'), findsNothing);
      expect(presenter.shownCallIds, ['call1']);
      expect(ringScreenCallIds(tester), ['call1']);
    });

    testWidgets('once the ringing call is declined, a new call rings '
        'normally', (tester) async {
      final (:container, :presenter) = await pumpWithPendingRings(tester);
      final declined = declinedCallIds();
      await deliverAndSettle(tester, invite(callId: 'call1'));
      await declineOnRingScreen(tester);
      expect(ringScreenCallIds(tester), isEmpty);
      expect(SystemRing.instance.ringing.value, isNull);

      await deliverAndSettle(
        tester,
        invite(callId: 'call2', senderId: '@carol:example.org'),
      );

      expect(declined, {'call1'});
      expect(container.read(resolvedCallIdsProvider), isNot(contains('call2')));
      expect(find.textContaining('Missed call'), findsNothing);
      expect(presenter.shownCallIds, ['call1', 'call2']);
      expect(ringScreenCallIds(tester), ['call2']);
      expect(SystemRing.instance.ringing.value?.callId, 'call2');
    });

    testWidgets('a call my other device already answered is not declined as '
        'busy while another call rings', (tester) async {
      final (:container, :presenter) = await pumpWithPendingRings(tester);
      await deliverAndSettle(tester, invite(callId: 'call1'));
      answerOnMyOtherDevice('call2');
      final declined = declinedCallIds();

      await deliverAndSettle(
        tester,
        invite(callId: 'call2', senderId: '@carol:example.org'),
      );

      expect(declined, isEmpty);
      expect(find.textContaining('Missed call'), findsNothing);
      expect(container.read(resolvedCallIdsProvider), contains('call2'));
      expect(presenter.shownCallIds, ['call1']);
      expect(ringScreenCallIds(tester), ['call1']);
      expect(SystemRing.instance.ringing.value?.callId, 'call1');
    });

    testWidgets('a call my other device already answered never rings', (
      tester,
    ) async {
      final (:container, :presenter) = await pumpWithPendingRings(tester);
      answerOnMyOtherDevice('call1');
      final declined = declinedCallIds();

      await deliverAndSettle(tester, invite(callId: 'call1'));

      expect(ringScreenCallIds(tester), isEmpty);
      expect(presenter.shownCallIds, isEmpty);
      expect(container.read(resolvedCallIdsProvider), contains('call1'));
      expect(declined, isEmpty);
      expect(find.textContaining('Missed call'), findsNothing);
      expect(SystemRing.instance.ringing.value, isNull);
    });

    testWidgets('a call my other device already answered takes down the ring '
        'the push already posted for it', (tester) async {
      final callStyle = installFakeCallStyleChannel();
      const vibration = MethodChannel('zuno/vibration');
      messenger.setMockMethodCallHandler(vibration, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(vibration, null));
      await pumpRoomList(tester);
      final prefs = await SharedPreferences.getInstance();
      await saveRingingCall(prefs, (
        roomId: room.id,
        callId: 'call1',
        callerId: '@bob:example.org',
        isVideo: false,
      ));
      answerOnMyOtherDevice('call1');
      callStyle.clear();

      await deliverAndSettle(tester, invite(callId: 'call1'));

      expect(callStyle.calls.map((call) => call.method), [
        'cancelIncomingCallStyle',
      ]);
      expect(readRingingCall(prefs), isNull);
      expect(ringScreenCallIds(tester), isEmpty);
    });
  });
}
