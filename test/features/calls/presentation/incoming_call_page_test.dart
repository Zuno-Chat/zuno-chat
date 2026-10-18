import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart' hide CallSession;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/matrixrtc/call_decline.dart';
import 'package:zuno/core/calls/matrixrtc/call_session.dart';
import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';
import 'package:zuno/core/calls/matrixrtc/incoming_call.dart';
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_provider.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/calls/notifications/pending_call_notification_action_provider.dart';
import 'package:zuno/core/calls/notifications/ringing_call_provider.dart';
import 'package:zuno/core/calls/platform/system_ring.dart';
import 'package:zuno/core/l10n/l10n.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/core/ui/zuno_colors.dart';
import 'package:zuno/features/calls/presentation/incoming_call_page.dart';

import '../../../helpers/fake_calls_channel.dart';
import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/native_method_calls.dart';
import '../../../helpers/platform_capabilities.dart';

class _PartialProfilesDatabaseApi extends SendCapableFakeDatabaseApi {
  final Map<String, User> partialRoomProfiles = {};

  @override
  Future<User?> getUser(String userId, Room room) async =>
      partialRoomProfiles[userId];
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  final events = <String>[];

  @override
  void didPush(Route<void> route, Route<void>? previousRoute) =>
      events.add('push');

  @override
  void didReplace({Route<void>? newRoute, Route<void>? oldRoute}) =>
      events.add('replace');

  @override
  void didPop(Route<void> route, Route<void>? previousRoute) =>
      events.add('pop');

  @override
  void didRemove(Route<void> route, Route<void>? previousRoute) =>
      events.add('remove');
}

Future<void> tapAndRunAsync(WidgetTester tester, Finder icon) async {
  final button = iconButtonFor(tester, icon);
  await tester.runAsync(() async {
    button.onPressed!.call();
    await Future<void>.delayed(Duration.zero);
  });
}

IconButton iconButtonFor(WidgetTester tester, Finder icon) =>
    tester.widget<IconButton>(
      find.ancestor(of: icon, matching: find.byType(IconButton)),
    );

Future<void> settleRealAsync(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late Room room;
  late _PartialProfilesDatabaseApi db;
  late SharedPreferences prefs;
  late GlobalKey<NavigatorState> navigatorKey;
  late _RecordingNavigatorObserver observer;
  late RecordedMethodCalls callsLog;
  late List<String> sentEvents;
  late List<String> requests;
  Completer<void>? sendGate;
  http.Response? sendReply;

  setUp(() async {
    sendGate = null;
    sendReply = null;
    callsLog = installFakeCallsChannel();
    installFakeLocalNotifications();

    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();

    db = _PartialProfilesDatabaseApi();
    sentEvents = [];
    requests = [];
    client = buildTestClient(
      userId: '@me:example.org',
      deviceId: 'DEVICE',
      database: db,
      httpClient: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.method == 'PUT' && request.url.path.contains('/send/')) {
          sentEvents.add(request.url.path);
          await sendGate?.future;
          if (sendReply case final reply?) return reply;
        }
        return http.Response(jsonEncode({'event_id': r'$evt'}), 200);
      }),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    room = buildTestRoom(client);

    navigatorKey = GlobalKey<NavigatorState>();
    observer = _RecordingNavigatorObserver();
  });

  List<Object?> lockscreenShows() => [
    for (final args in callsLog.argsOf('setShowOverLockscreen'))
      (args! as Map)['show'],
  ];

  IncomingCall call({
    String callId = 'call1',
    String callerId = '@bob:example.org',
    CallKind kind = CallKind.voice,
  }) =>
      IncomingCall(room: room, callId: callId, callerId: callerId, kind: kind);

  Future<ProviderContainer> pumpShell(WidgetTester tester) async {
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
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              navigatorKey: navigatorKey,
              navigatorObservers: [observer],
              home: const Scaffold(body: Text('room list')),
            );
          },
        ),
      ),
    );
    return container;
  }

  List<SystemRingingCall?> recordSystemRing() {
    final changes = <SystemRingingCall?>[];
    void record() => changes.add(SystemRing.instance.ringing.value);
    SystemRing.instance.ringing.addListener(record);
    addTearDown(() => SystemRing.instance.ringing.removeListener(record));
    return changes;
  }

  void pushIncomingCall(IncomingCall incomingCall) {
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => IncomingCallPage(call: incomingCall),
      ),
    );
  }

  group('synchronous initState guards (race with something else)', () {
    testWidgets('a ring screen for the call answered here hands off to it, '
        'though answering settled the call', (tester) async {
      final container = await pumpShell(tester);
      final answered = container
          .read(activeCallProvider.notifier)
          .answer(call())!;
      addTearDown(answered.dispose);
      expect(container.read(resolvedCallIdsProvider), contains('call1'));

      pushIncomingCall(call());
      await tester.pumpAndSettle();

      expect(find.byType(IncomingCallPage), findsNothing);
      expect(lockscreenShows(), isNot(contains(false)));
      expect(container.read(activeCallProvider), same(answered));
    });

    testWidgets('dismisses immediately, never taking the system ring, when '
        'resolvedCallIdsProvider already has this call_id', (tester) async {
      final container = await pumpShell(tester);
      container.read(resolvedCallIdsProvider.notifier).markResolved('call1');
      final ringChanges = recordSystemRing();

      pushIncomingCall(call());
      await tester.pumpAndSettle();

      expect(find.byType(IncomingCallPage), findsNothing);
      expect(find.text('room list'), findsOneWidget);
      expect(ringChanges, isEmpty);
    });

    testWidgets(
      'hands off without creating a second session or taking the system '
      'ring when activeCallProvider already holds this call_id',
      (tester) async {
        final container = await pumpShell(tester);
        final existing = CallSession.forIncoming(
          room: room,
          callId: 'call1',
          kind: CallKind.voice,
        );
        addTearDown(existing.dispose);
        container.read(activeCallProvider.notifier).set(existing);
        final ringChanges = recordSystemRing();

        pushIncomingCall(call());
        await tester.pumpAndSettle();

        expect(find.byType(IncomingCallPage), findsNothing);
        expect(find.text('room list'), findsOneWidget);
        expect(container.read(activeCallProvider), same(existing));
        expect(ringChanges, isEmpty);
      },
    );

    testWidgets(
      'performs and consumes a pending decline action found at initState',
      (tester) async {
        final container = await pumpShell(tester);
        container.read(pendingCallNotificationActionProvider);
        CallNotificationService.instance.onActionForTest(
          CallNotificationResponse(
            action: CallNotificationAction.decline,
            call: (
              roomId: room.id,
              callId: 'call1',
              callerId: '@bob:example.org',
              isVideo: false,
            ),
          ),
        );
        await tester.pump();
        expect(
          container.read(pendingCallNotificationActionProvider)?.action,
          CallNotificationAction.decline,
        );

        pushIncomingCall(call());
        await settleRealAsync(tester);

        expect(find.byType(IncomingCallPage), findsNothing);
        expect(find.text('room list'), findsOneWidget);
        expect(container.read(pendingCallNotificationActionProvider), isNull);
      },
    );

    testWidgets(
      'performs and consumes a pending accept action found at initState',
      (tester) async {
        final container = await pumpShell(tester);
        container.read(pendingCallNotificationActionProvider);
        CallNotificationService.instance.onActionForTest(
          CallNotificationResponse(
            action: CallNotificationAction.accept,
            call: (
              roomId: room.id,
              callId: 'call1',
              callerId: '@bob:example.org',
              isVideo: false,
            ),
          ),
        );
        await tester.pump();
        expect(
          container.read(pendingCallNotificationActionProvider)?.action,
          CallNotificationAction.accept,
        );

        pushIncomingCall(call());
        await tester.pump();

        final session = container.read(activeCallProvider);
        expect(session, isNotNull);
        expect(session!.callId, 'call1');
        addTearDown(session.dispose);
        expect(container.read(pendingCallNotificationActionProvider), isNull);
      },
    );

    testWidgets('ignores a pending action for a different call_id', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      container.read(pendingCallNotificationActionProvider);
      CallNotificationService.instance.onActionForTest(
        CallNotificationResponse(
          action: CallNotificationAction.decline,
          call: (
            roomId: room.id,
            callId: 'some-other-call',
            callerId: '@bob:example.org',
            isVideo: false,
          ),
        ),
      );
      await tester.pump();

      pushIncomingCall(call());
      await tester.pumpAndSettle();

      expect(find.byType(IncomingCallPage), findsOneWidget);
      expect(
        container.read(pendingCallNotificationActionProvider)?.call.callId,
        'some-other-call',
      );
    });
  });

  group('live updates while mounted', () {
    testWidgets(
      'dismisses live when resolvedCallIdsProvider updates while mounted',
      (tester) async {
        final container = await pumpShell(tester);
        pushIncomingCall(call());
        await tester.pumpAndSettle();
        expect(find.byType(IncomingCallPage), findsOneWidget);
        expect(RingingCall.instance.callId, 'call1');

        container.read(resolvedCallIdsProvider.notifier).markResolved('call1');
        await tester.pumpAndSettle();

        expect(find.byType(IncomingCallPage), findsNothing);
        expect(find.text('room list'), findsOneWidget);
        expect(RingingCall.instance.callId, isNull);
      },
    );

    for (final status in [CallSummaryStatus.missed, CallSummaryStatus.ended]) {
      testWidgets('dismisses when the caller hangs up before we respond, on a '
          'matching ${status.name} call_summary', (tester) async {
        await pumpShell(tester);
        pushIncomingCall(call());
        await tester.pumpAndSettle();

        client.onTimelineEvent.add(
          buildTestEvent(
            room,
            eventId: r'$summary',
            senderId: '@bob:example.org',
            content: CallSummary(
              callId: 'call1',
              kind: 'voice',
              status: status,
              durationMs: 0,
            ).toMessageContent(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(IncomingCallPage), findsNothing);
        expect(find.text('room list'), findsOneWidget);
        expect(RingingCall.instance.callId, isNull);
      });
    }

    testWidgets(
      'does not dismiss for a call_summary naming a different call_id',
      (tester) async {
        await pumpShell(tester);
        pushIncomingCall(call());
        await tester.pumpAndSettle();

        const summary = CallSummary(
          callId: 'some-other-call',
          kind: 'voice',
          status: CallSummaryStatus.missed,
          durationMs: 0,
        );
        client.onTimelineEvent.add(
          buildTestEvent(
            room,
            eventId: r'$summary',
            senderId: '@bob:example.org',
            content: summary.toMessageContent(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(IncomingCallPage), findsOneWidget);
      },
    );

    testWidgets('does not dismiss for a non-summary event', (tester) async {
      await pumpShell(tester);
      pushIncomingCall(call());
      await tester.pumpAndSettle();

      client.onTimelineEvent.add(
        buildTestEvent(
          room,
          eventId: r'$msg',
          senderId: '@bob:example.org',
          content: {'msgtype': 'm.text', 'body': 'hello', 'call_id': 'call1'},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(IncomingCallPage), findsOneWidget);
    });
  });

  group('Decline', () {
    testWidgets('sends a decline and dismisses', (tester) async {
      await pumpShell(tester);
      pushIncomingCall(call());
      await tester.pumpAndSettle();
      expect(RingingCall.instance.callId, 'call1');

      await tapAndRunAsync(tester, find.byIcon(Icons.call_end));
      await tester.pumpAndSettle();

      expect(find.byType(IncomingCallPage), findsNothing);
      expect(find.text('room list'), findsOneWidget);
      expect(RingingCall.instance.callId, isNull);
      expect(lockscreenShows(), containsAll([true, false]));
      expect(sentEvents.single, endsWith('/${callDeclineTxid('call1')}'));
    });

    testWidgets('stops ringing and closes before the decline is sent', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      pushIncomingCall(call());
      await tester.pumpAndSettle();
      sendGate = Completer<void>();

      await tester.tap(find.byIcon(Icons.call_end));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      expect(find.byType(IncomingCallPage), findsNothing);
      expect(RingingCall.instance.callId, isNull);
      expect(container.read(resolvedCallIdsProvider), contains('call1'));
      expect(sentEvents.single, endsWith('/${callDeclineTxid('call1')}'));
      sendGate!.complete();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    });

    testWidgets('a decline the server refuses still closes the page', (
      tester,
    ) async {
      await pumpShell(tester);
      pushIncomingCall(call());
      await tester.pumpAndSettle();
      sendReply = http.Response(
        jsonEncode({'errcode': 'M_FORBIDDEN', 'error': 'no'}),
        403,
      );

      await tester.tap(find.byIcon(Icons.call_end));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      expect(find.byType(IncomingCallPage), findsNothing);
      expect(find.text('room list'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a fast double-tap only sends one decline and dismisses once', (
      tester,
    ) async {
      await pumpShell(tester);
      pushIncomingCall(call());
      await tester.pumpAndSettle();

      final button = iconButtonFor(tester, find.byIcon(Icons.call_end));
      button.onPressed!.call();
      button.onPressed!.call();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      expect(sentEvents, hasLength(1));
      expect(sentEvents.single, endsWith('/${callDeclineTxid('call1')}'));
      expect(find.byType(IncomingCallPage), findsNothing);
      expect(observer.events.where((e) => e == 'pop'), hasLength(1));
    });

    testWidgets(
      'a Decline tap after Accept already resolved this call is a no-op',
      (tester) async {
        final container = await pumpShell(tester);
        pushIncomingCall(call());
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.call));
        final session = container.read(activeCallProvider);
        expect(session?.callId, 'call1');
        addTearDown(session!.dispose);

        final declineButton = iconButtonFor(
          tester,
          find.byIcon(Icons.call_end),
        );
        declineButton.onPressed!.call();

        expect(container.read(activeCallProvider), same(session));
        expect(observer.events.where((e) => e == 'replace'), hasLength(1));
      },
    );
  });

  group('Accept', () {
    testWidgets('sets activeCallProvider and starts navigating away without '
        'awaiting session.accept()', (tester) async {
      final container = await pumpShell(tester);
      pushIncomingCall(call());
      await tester.pumpAndSettle();
      expect(container.read(activeCallProvider), isNull);

      await tester.tap(find.byIcon(Icons.call));

      final session = container.read(activeCallProvider);
      expect(session, isNotNull);
      expect(session!.callId, 'call1');
      addTearDown(session.dispose);
      expect(observer.events, contains('replace'));
      expect(lockscreenShows(), contains(true));
    });

    testWidgets(
      'a video call also sets activeCallProvider and navigates away, with '
      'the video kind carried through',
      (tester) async {
        final container = await pumpShell(tester);
        pushIncomingCall(call(kind: CallKind.video, callId: 'call2'));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.videocam));

        final session = container.read(activeCallProvider);
        expect(session, isNotNull);
        expect(session!.callId, 'call2');
        expect(session.kind, CallKind.video);
        addTearDown(session.dispose);
        expect(observer.events, contains('replace'));
      },
    );

    testWidgets(
      'a fast double-tap on Accept only creates one session and navigates '
      'once',
      (tester) async {
        final container = await pumpShell(tester);
        pushIncomingCall(call());
        await tester.pumpAndSettle();

        final button = iconButtonFor(tester, find.byIcon(Icons.call));
        button.onPressed!.call();
        button.onPressed!.call();

        final session = container.read(activeCallProvider);
        expect(session?.callId, 'call1');
        addTearDown(session!.dispose);
        expect(observer.events.where((e) => e == 'replace'), hasLength(1));
      },
    );

    testWidgets(
      'hands off instead of double-accepting when activeCallProvider is '
      'set after this page already built',
      (tester) async {
        final container = await pumpShell(tester);
        pushIncomingCall(call());
        await tester.pumpAndSettle();

        final existing = CallSession.forIncoming(
          room: room,
          callId: 'call1',
          kind: CallKind.voice,
        );
        addTearDown(existing.dispose);
        container.read(activeCallProvider.notifier).set(existing);

        await tester.tap(find.byIcon(Icons.call));
        await tester.pumpAndSettle();

        expect(find.byType(IncomingCallPage), findsNothing);
        expect(find.text('room list'), findsOneWidget);
        expect(container.read(activeCallProvider), same(existing));
        expect(RingingCall.instance.callId, isNull);
        expect(lockscreenShows(), contains(true));
        expect(lockscreenShows(), isNot(contains(false)));
      },
    );
  });

  group('who is calling', () {
    void markDirect() => client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        '@bob:example.org': [room.id],
      },
    );

    void nameRoom() => room.setState(
      buildTestEvent(
        room,
        eventId: r'$name',
        senderId: '@bob:example.org',
        type: EventTypes.RoomName,
        stateKey: '',
        content: {'name': 'Weekend hike'},
      ),
    );

    testWidgets('a one-to-one call shows the caller\'s instant fallback name '
        'on first build', (tester) async {
      markDirect();
      await pumpShell(tester);
      pushIncomingCall(call());
      await tester.pump();
      expect(find.text('Bob', skipOffstage: false), findsOneWidget);
    });

    testWidgets('a one-to-one call updates to the caller\'s resolved display '
        'name once it lands', (tester) async {
      markDirect();
      db.partialRoomProfiles['@bob:example.org'] = User(
        '@bob:example.org',
        displayName: 'Bob Resolved',
        room: room,
      );
      await pumpShell(tester);
      pushIncomingCall(call());
      await tester.pumpAndSettle();

      expect(find.text('Bob Resolved'), findsOneWidget);
      expect(find.text('Bob'), findsNothing);
    });

    testWidgets(
      'an unresolvable caller renders the fallback indefinitely, without '
      'crashing',
      (tester) async {
        markDirect();
        await pumpShell(tester);
        pushIncomingCall(call());
        await tester.pumpAndSettle();

        expect(find.text('Bob'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a group call shows the group\'s name, with the caller this '
        'device knows under it', (tester) async {
      nameRoom();
      db.partialRoomProfiles['@bob:example.org'] = User(
        '@bob:example.org',
        displayName: 'Bob Resolved',
        room: room,
      );
      await pumpShell(tester);
      pushIncomingCall(call());
      await tester.pumpAndSettle();

      expect(find.text('Weekend hike'), findsOneWidget);
      expect(find.text('Bob Resolved'), findsOneWidget);
      expect(find.text('Incoming voice call'), findsOneWidget);
    });

    testWidgets('a group call from a caller this device does not know names '
        'no caller and asks the server nothing', (tester) async {
      nameRoom();
      await pumpShell(tester);
      pushIncomingCall(call());
      await tester.pumpAndSettle();

      expect(find.text('Weekend hike'), findsOneWidget);
      expect(find.text('Bob'), findsNothing);
      expect(requests, isEmpty);
    });
  });

  group('video vs. voice', () {
    testWidgets('a voice call shows the voice label and phone icon', (
      tester,
    ) async {
      await pumpShell(tester);
      pushIncomingCall(call(kind: CallKind.voice));
      await tester.pumpAndSettle();

      expect(find.text('Incoming voice call'), findsOneWidget);
      expect(find.text('Incoming video call'), findsNothing);
      expect(find.byIcon(Icons.call), findsOneWidget);
      expect(find.byIcon(Icons.videocam), findsNothing);
    });

    testWidgets('Decline is red, Accept is green, both named once and at '
        'least 72 px, on a dark screen', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpShell(tester);
      pushIncomingCall(call(kind: CallKind.voice, callId: 'look'));
      await tester.pumpAndSettle();

      for (final (label, icon, color) in [
        ('Decline', Icons.call_end, callEndColor),
        ('Accept', Icons.call, callAcceptColor),
      ]) {
        final button = iconButtonFor(tester, find.byIcon(icon));
        expect(
          button.style!.backgroundColor!.resolve(const {}),
          color,
          reason: label,
        );
        expect(button.tooltip, label);
        expect(
          tester.getSize(find.byTooltip(label)).shortestSide,
          greaterThanOrEqualTo(72),
        );
        expect(find.bySemanticsLabel(label), findsNothing);
      }
      expect(
        Theme.of(tester.element(find.text('Incoming voice call'))).brightness,
        Brightness.dark,
      );
      handle.dispose();
    });

    testWidgets('a video call shows the video label and camera icon', (
      tester,
    ) async {
      await pumpShell(tester);
      pushIncomingCall(call(kind: CallKind.video, callId: 'call2'));
      await tester.pumpAndSettle();

      expect(find.text('Incoming video call'), findsOneWidget);
      expect(find.text('Incoming voice call'), findsNothing);
      expect(find.byIcon(Icons.videocam), findsOneWidget);
      expect(find.byIcon(Icons.call), findsNothing);
    });
  });

  group('_dismiss(): pop vs. removeRoute', () {
    testWidgets('removes its own route (not popping the top one) when another '
        'screen was pushed on top of it', (tester) async {
      final container = await pumpShell(tester);
      pushIncomingCall(call());
      await tester.pumpAndSettle();

      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('on top')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('on top'), findsOneWidget);

      container.read(resolvedCallIdsProvider.notifier).markResolved('call1');
      await tester.pumpAndSettle();

      expect(find.text('on top'), findsOneWidget);
      expect(find.byType(IncomingCallPage), findsNothing);
    });
  });

  group('back gesture (PopScope)', () {
    testWidgets(
      'a bare pop attempt (the back gesture) does not dismiss the page',
      (tester) async {
        await pumpShell(tester);
        pushIncomingCall(call());
        await tester.pumpAndSettle();

        final handled = await navigatorKey.currentState!.maybePop();
        await tester.pumpAndSettle();

        expect(handled, isTrue);
        expect(find.byType(IncomingCallPage), findsOneWidget);
      },
    );
  });

  group('two calls in sequence', () {
    testWidgets('a fresh call after the first resolves rings independently', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      pushIncomingCall(call());
      await tester.pumpAndSettle();
      expect(RingingCall.instance.callId, 'call1');

      container.read(resolvedCallIdsProvider.notifier).markResolved('call1');
      await tester.pumpAndSettle();
      expect(find.byType(IncomingCallPage), findsNothing);
      expect(RingingCall.instance.callId, isNull);

      pushIncomingCall(call(callId: 'call2'));
      await tester.pumpAndSettle();

      expect(find.byType(IncomingCallPage), findsOneWidget);
      expect(RingingCall.instance.callId, 'call2');
      expect(container.read(resolvedCallIdsProvider), {'call1'});
    });
  });

  group('tap targets', () {
    testWidgets(
      'the Decline/Accept captions are not tap targets on their own',
      (tester) async {
        await pumpShell(tester);
        pushIncomingCall(call());
        await tester.pumpAndSettle();

        expect(
          find.ancestor(
            of: find.text('Decline'),
            matching: find.byType(IconButton),
          ),
          findsNothing,
        );

        await tester.tap(find.text('Decline'));
        await tester.pumpAndSettle();

        expect(sentEvents, isEmpty);
        expect(find.byType(IncomingCallPage), findsOneWidget);
      },
    );
  });

  group('system ring', () {
    setUp(() => ambientCapabilities = androidCapabilities);

    Future<void> ring(WidgetTester tester) async {
      pushIncomingCall(call());
      await tester.pumpAndSettle();
      expect(SystemRing.instance.ringing.value?.callId, 'call1');
    }

    testWidgets('holds the system ring for its call while it rings', (
      tester,
    ) async {
      await pumpShell(tester);

      pushIncomingCall(call());
      await tester.pumpAndSettle();

      expect(find.byType(IncomingCallPage), findsOneWidget);
      expect(SystemRing.instance.ringing.value, (
        roomId: room.id,
        callId: 'call1',
      ));
    });

    testWidgets('releases it the moment Decline dismisses the page', (
      tester,
    ) async {
      await pumpShell(tester);
      await ring(tester);

      await tapAndRunAsync(tester, find.byIcon(Icons.call_end));

      expect(SystemRing.instance.ringing.value, isNull);
      expect(find.byType(IncomingCallPage), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(IncomingCallPage), findsNothing);
    });

    testWidgets('releases it on Accept, once the call is already active', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      await ring(tester);
      String? activeCallIdAtRelease;
      void onRingChanged() {
        if (SystemRing.instance.ringing.value != null) return;
        activeCallIdAtRelease = container.read(activeCallProvider)?.callId;
      }

      SystemRing.instance.ringing.addListener(onRingChanged);
      addTearDown(
        () => SystemRing.instance.ringing.removeListener(onRingChanged),
      );

      await tester.tap(find.byIcon(Icons.call));

      final session = container.read(activeCallProvider);
      expect(session?.callId, 'call1');
      addTearDown(session!.dispose);
      expect(SystemRing.instance.ringing.value, isNull);
      expect(activeCallIdAtRelease, 'call1');
    });

    testWidgets('releases it the moment the caller hangs up', (tester) async {
      await pumpShell(tester);
      await ring(tester);

      client.onTimelineEvent.add(
        buildTestEvent(
          room,
          eventId: r'$summary',
          senderId: '@bob:example.org',
          content: const CallSummary(
            callId: 'call1',
            kind: 'voice',
            status: CallSummaryStatus.missed,
            durationMs: 0,
          ).toMessageContent(),
        ),
      );
      await tester.pump();

      expect(SystemRing.instance.ringing.value, isNull);
      expect(find.byType(IncomingCallPage), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(IncomingCallPage), findsNothing);
    });

    testWidgets('releases it the moment the call is resolved', (tester) async {
      final container = await pumpShell(tester);
      await ring(tester);

      container.read(resolvedCallIdsProvider.notifier).markResolved('call1');
      await tester.pump();

      expect(SystemRing.instance.ringing.value, isNull);
      expect(find.byType(IncomingCallPage), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(IncomingCallPage), findsNothing);
    });

    testWidgets('releases it when the page is disposed', (tester) async {
      await pumpShell(tester);
      await ring(tester);

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();

      expect(find.byType(IncomingCallPage), findsNothing);
      expect(SystemRing.instance.ringing.value, isNull);
    });

    testWidgets('on iOS never takes it, from ringing through Decline', (
      tester,
    ) async {
      ambientCapabilities = iosCapabilities;
      await pumpShell(tester);
      final ringChanges = recordSystemRing();

      pushIncomingCall(call());
      await tester.pumpAndSettle();
      expect(find.byType(IncomingCallPage), findsOneWidget);
      await tapAndRunAsync(tester, find.byIcon(Icons.call_end));
      await tester.pumpAndSettle();

      expect(find.byType(IncomingCallPage), findsNothing);
      expect(ringChanges, isEmpty);
    });
  });
}
