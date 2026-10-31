import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' hide CallSession;
import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/matrixrtc/call_session.dart';
import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';
import 'package:zuno/core/calls/matrixrtc/incoming_call.dart';
import 'package:zuno/core/calls/matrixrtc/incoming_call_provider.dart';
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_provider.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/notifications/ringing_call_provider.dart';
import 'package:zuno/core/calls/platform/incoming_call_presenter.dart';
import 'package:zuno/core/calls/platform/system_ring.dart';
import 'package:zuno/core/calls/ring_coordinator.dart';
import 'package:zuno/core/errors/global_error_handler.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/navigation/global_navigator.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/features/calls/presentation/incoming_call_page.dart';

import '../../helpers/fake_calls_channel.dart';
import '../../helpers/fake_http.dart';
import '../../helpers/fake_local_notifications.dart';
import '../../helpers/fake_matrix.dart';
import '../../helpers/native_method_calls.dart';
import '../../helpers/platform_capabilities.dart';
import '../../helpers/preferences_container.dart';
import '../../helpers/sent_call_declines.dart';

class _PendingRingPresenter extends NoopIncomingCallPresenter {
  final shownCallIds = <String>[];
  final shownWaiting = <bool>[];

  @override
  Future<RingOutcome> showIncoming({
    required String name,
    String? caller,
    required String callerId,
    required bool isVideo,
    required String roomId,
    required String callId,
    bool isGroupCall = false,
    Uint8List? avatarBytes,
    bool waiting = false,
    Duration? ringFor,
  }) {
    shownCallIds.add(callId);
    shownWaiting.add(waiting);
    return Completer<RingOutcome>().future;
  }

  @override
  Future<void> cancelIncoming({
    String? roomId,
    String? callId,
    RingEnd end = RingEnd.remoteEnded,
  }) async {}
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
  late Client client;
  late SentCallDeclines declines;
  late Room room;
  late RecordedMethodCalls native;
  Object? ringReply;

  setUp(() {
    ambientCapabilities = androidCapabilities;
    ringRateLimiter.clear();
    ringReply = null;
    installFakeLocalNotifications();
    native = installFakeCallsChannel(
      reply: (call) => call.method == 'reportIncomingCall' ? ringReply : null,
    );

    declines = SentCallDeclines();
    client = buildTestClient(
      userId: '@me:example.org',
      deviceId: 'THISPHONE',
      database: SendCapableFakeDatabaseApi(),
      httpClient: FakeHttpClient((request) async {
        declines.record(request);
        return http.Response(jsonEncode({'event_id': r'$evt'}), 200);
      }),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    room = buildTestRoom(client);
  });

  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    final container = await containerWithPreferences(
      {},
      overrides: [matrixClientProvider.overrideWithValue(client), ...overrides],
    );
    container.listen(ringCoordinatorProvider, (_, _) {});
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          navigatorKey: globalNavigatorKey,
          scaffoldMessengerKey: globalScaffoldMessengerKey,
          home: const Scaffold(body: Text('chats')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<({ProviderContainer container, _PendingRingPresenter presenter})>
  pumpWithPendingRings(WidgetTester tester) async {
    final presenter = _PendingRingPresenter();
    final container = await pumpApp(
      tester,
      overrides: [incomingCallPresenterProvider.overrideWithValue(presenter)],
    );
    return (container: container, presenter: presenter);
  }

  Future<void> deliverAndSettle(WidgetTester tester, Event event) async {
    client.onTimelineEvent.add(event);
    await tester.pump();
    await tester.pumpAndSettle();
  }

  CallSession onACall(ProviderContainer container) {
    final session = CallSession.forIncoming(
      room: room,
      callId: 'active-call',
      kind: CallKind.voice,
    );
    addTearDown(session.dispose);
    container.read(activeCallProvider.notifier).set(session);
    return session;
  }

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

  List<String?> declinedCallIds() => declines.watch();

  List<String> ringScreenCallIds(WidgetTester tester) => [
    for (final page in tester.widgetList<IncomingCallPage>(
      find.byType(IncomingCallPage, skipOffstage: false),
    ))
      page.call.callId,
  ];

  Future<void> declineOnRingScreen(WidgetTester tester) async {
    await tester.tap(find.widgetWithIcon(IconButton, Icons.call_end));
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

  testWidgets('a second incoming call while already on one rings as a '
      'waiting call on its ring screen, and is never declined', (tester) async {
    final (:container, :presenter) = await pumpWithPendingRings(tester);
    final session = onACall(container);
    final declined = declinedCallIds();

    await deliverAndSettle(
      tester,
      invite(callId: 'call2', senderId: '@carol:example.org'),
    );

    expect(ringScreenCallIds(tester), ['call2']);
    expect(presenter.shownCallIds, ['call2']);
    expect(presenter.shownWaiting, [true]);
    expect(declined, isEmpty);
    expect(container.read(activeCallProvider), same(session));
    expect(find.text('Missed call from Carol'), findsNothing);
  });

  testWidgets('a call with no other call on the line rings as a normal '
      'ring', (tester) async {
    final (container: _, :presenter) = await pumpWithPendingRings(tester);

    await deliverAndSettle(tester, invite(callId: 'call1'));

    expect(presenter.shownWaiting, [false]);
  });

  group('android', () {
    testWidgets('the invite for a call answered from its ring before the first '
        'sync is neither declined nor announced as missed', (tester) async {
      final container = await pumpApp(tester);
      final answered = container
          .read(activeCallProvider.notifier)
          .answer(
            IncomingCall(
              room: room,
              callId: 'call1',
              callerId: '@bob:example.org',
              kind: CallKind.voice,
            ),
          )!;
      addTearDown(answered.dispose);
      final declined = declinedCallIds();

      await deliverAndSettle(tester, invite(callId: 'call1'));

      expect(declined, isEmpty);
      expect(find.textContaining('Missed call'), findsNothing);
      expect(container.read(activeCallProvider), same(answered));
    });

    testWidgets('the ring screen opens at once, without waiting on the ring '
        'notification', (tester) async {
      final (:presenter, container: _) = await pumpWithPendingRings(tester);

      await deliverAndSettle(tester, invite(callId: 'call1'));

      expect(presenter.shownCallIds, ['call1']);
      expect(find.byType(IncomingCallPage), findsOneWidget);
      expect(native.argsOf('reportIncomingCall'), isEmpty);
    });

    testWidgets('the ring screen an invite opened closes when the caller '
        'hangs up', (tester) async {
      await pumpWithPendingRings(tester);

      await deliverAndSettle(tester, invite(callId: 'call1'));
      expect(ringScreenCallIds(tester), ['call1']);

      await deliverAndSettle(tester, hangUp(callId: 'call1'));

      expect(ringScreenCallIds(tester), isEmpty);
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

      expect(declined, ['call2']);
      expect(container.read(resolvedCallIdsProvider), contains('call2'));
      expect(find.text('Missed call from Carol'), findsOneWidget);
      expect(ringScreenCallIds(tester), ['call1']);
      expect(presenter.shownCallIds, ['call1']);
      expect(SystemRing.instance.ringing.value?.callId, 'call1');
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

      expect(declined, ['call1']);
      expect(container.read(resolvedCallIdsProvider), isNot(contains('call2')));
      expect(find.textContaining('Missed call'), findsNothing);
      expect(presenter.shownCallIds, ['call1', 'call2']);
      expect(ringScreenCallIds(tester), ['call2']);
      expect(SystemRing.instance.ringing.value?.callId, 'call2');
    });
  });

  group('the ring screen', () {
    IncomingCall bobsCall([String callId = 'call1']) => IncomingCall(
      room: room,
      callId: callId,
      callerId: '@bob:example.org',
      kind: CallKind.voice,
    );

    bool present(ProviderContainer container, IncomingCall call) =>
        container.read(ringScreenProvider.notifier).present(call);

    testWidgets('opens for a call still ringing and marks it ringing until it '
        'closes', (tester) async {
      final container = await pumpApp(tester);

      expect(present(container, bobsCall()), isTrue);
      expect(RingingCall.instance.callId, 'call1');
      await tester.pumpAndSettle();
      expect(ringScreenCallIds(tester), ['call1']);

      container.read(resolvedCallIdsProvider.notifier).markResolved('call1');
      await tester.pumpAndSettle();

      expect(ringScreenCallIds(tester), isEmpty);
      expect(RingingCall.instance.callId, isNull);
    });

    testWidgets('opens once, however many times it is asked before it builds', (
      tester,
    ) async {
      final container = await pumpApp(tester);

      expect(present(container, bobsCall()), isTrue);
      expect(present(container, bobsCall()), isTrue);
      await tester.pumpAndSettle();

      expect(ringScreenCallIds(tester), ['call1']);
    });

    testWidgets('never opens for a call already over', (tester) async {
      final container = await pumpApp(tester);
      container.read(resolvedCallIdsProvider.notifier).markResolved('call1');

      expect(present(container, bobsCall()), isFalse);
      await tester.pumpAndSettle();

      expect(ringScreenCallIds(tester), isEmpty);
      expect(RingingCall.instance.callId, isNull);
    });

    testWidgets('never opens for the call already on the line', (tester) async {
      final container = await pumpApp(tester);
      final session = CallSession.forIncoming(
        room: room,
        callId: 'call1',
        kind: CallKind.voice,
      );
      addTearDown(session.dispose);
      container.read(activeCallProvider.notifier).set(session);

      expect(present(container, bobsCall()), isFalse);
      await tester.pumpAndSettle();

      expect(ringScreenCallIds(tester), isEmpty);
    });

    testWidgets('never opens while CallKit shows the ring', (tester) async {
      ambientCapabilities = iosCapabilities;
      final container = await pumpApp(
        tester,
        overrides: [
          platformCapabilitiesProvider.overrideWithValue(
            capabilitiesLike(iosCapabilities, voipRing: false),
          ),
        ],
      );
      SystemRing.instance.set(roomId: room.id, callId: 'call1');

      expect(present(container, bobsCall()), isFalse);
      await tester.pumpAndSettle();

      expect(ringScreenCallIds(tester), isEmpty);
      SystemRing.instance.clear('call1');
    });
  });
}
