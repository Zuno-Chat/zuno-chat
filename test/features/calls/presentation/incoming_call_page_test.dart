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

import 'package:zuno/core/ui/zuno_colors.dart';
import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/matrixrtc/call_session.dart';
import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';
import 'package:zuno/core/calls/matrixrtc/incoming_call.dart';
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_provider.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/calls/notifications/pending_call_notification_action_provider.dart';
import 'package:zuno/core/calls/notifications/ringing_call_provider.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/calls/presentation/incoming_call_page.dart';

import '../../../helpers/fake_matrix.dart';

class _SendCapableFakeDatabaseApi extends FakeDatabaseApi {
  @override
  Future<void> transaction(Future<void> Function() action) => action();

  final Map<String, User> partialRoomProfiles = {};

  @override
  Future<User?> getUser(String userId, Room room) async =>
      partialRoomProfiles[userId];

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

class _TestClient extends Client {
  _TestClient(super.clientName, {required super.database, super.httpClient});

  @override
  String? get deviceID => 'DEVICE';
}

class _ChannelLog {
  final calls = <MethodCall>[];
  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    return null;
  }

  bool has(String method, [Map<String, Object?>? arguments]) => calls.any(
    (c) =>
        c.method == method &&
        (arguments == null || _mapEquals(c.arguments as Map?, arguments)),
  );
}

bool _mapEquals(Map? a, Map<String, Object?>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (a[key] != b[key]) return false;
  }
  return true;
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
  await tester.runAsync(() => button.onPressed!.call() as dynamic);
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
  late _SendCapableFakeDatabaseApi db;
  late SharedPreferences prefs;
  late GlobalKey<NavigatorState> navigatorKey;
  late _RecordingNavigatorObserver observer;
  late _ChannelLog callsLog;

  setUp(() async {
    callsLog = _ChannelLog();
    messenger.setMockMethodCallHandler(
      notificationsChannel,
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(callsChannel, callsLog.handle);

    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();

    db = _SendCapableFakeDatabaseApi();
    client = _TestClient(
      'test',
      database: db,
      httpClient: MockClient(
        (request) async =>
            http.Response(jsonEncode({'event_id': r'$evt'}), 200),
      ),
    );
    client.setUserId('@me:example.org');
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    room = buildTestRoom(client);

    navigatorKey = GlobalKey<NavigatorState>();
    observer = _RecordingNavigatorObserver();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(notificationsChannel, null);
    messenger.setMockMethodCallHandler(callsChannel, null);
  });

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

  void pushIncomingCall(IncomingCall incomingCall) {
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => IncomingCallPage(call: incomingCall),
      ),
    );
  }

  group('synchronous initState guards (race with something else)', () {
    testWidgets(
      'dismisses immediately when resolvedCallIdsProvider already has this call_id',
      (tester) async {
        final container = await pumpShell(tester);
        container.read(resolvedCallIdsProvider.notifier).markResolved('call1');

        pushIncomingCall(call());
        await tester.pumpAndSettle();

        expect(find.byType(IncomingCallPage), findsNothing);
        expect(find.text('room list'), findsOneWidget);
      },
    );

    testWidgets(
      'hands off without creating a second session when activeCallProvider '
      'already holds this call_id',
      (tester) async {
        final container = await pumpShell(tester);
        final existing = CallSession.forIncoming(
          room: room,
          callId: 'call1',
          kind: CallKind.voice,
        );
        addTearDown(existing.dispose);
        container.read(activeCallProvider.notifier).set(existing);

        pushIncomingCall(call());
        await tester.pumpAndSettle();

        expect(find.byType(IncomingCallPage), findsNothing);
        expect(find.text('room list'), findsOneWidget);
        expect(container.read(activeCallProvider), same(existing));
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

    testWidgets(
      'dismisses when the caller hangs up before we respond (matching '
      'call_summary event)',
      (tester) async {
        await pumpShell(tester);
        pushIncomingCall(call());
        await tester.pumpAndSettle();

        const summary = CallSummary(
          callId: 'call1',
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

        expect(find.byType(IncomingCallPage), findsNothing);
        expect(find.text('room list'), findsOneWidget);
        expect(RingingCall.instance.callId, isNull);
      },
    );

    testWidgets('dismisses for a call_summary with a non-missed status too '
        '(e.g. ended)', (tester) async {
      await pumpShell(tester);
      pushIncomingCall(call());
      await tester.pumpAndSettle();

      const summary = CallSummary(
        callId: 'call1',
        kind: 'voice',
        status: CallSummaryStatus.ended,
        durationMs: 42000,
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

      expect(find.byType(IncomingCallPage), findsNothing);
      expect(find.text('room list'), findsOneWidget);
    });

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
      expect(callsLog.has('setShowOverLockscreen', {'show': true}), isTrue);
      expect(callsLog.has('setShowOverLockscreen', {'show': false}), isTrue);
    });

    testWidgets('a fast double-tap only sends one decline and dismisses once', (
      tester,
    ) async {
      await pumpShell(tester);
      pushIncomingCall(call());
      await tester.pumpAndSettle();

      final declineTxIds = <String?>{};
      client.onTimelineEvent.stream.listen((e) {
        if (e.messageType == callDeclineMsgtype) {
          declineTxIds.add(e.unsigned?.tryGet<String>('transaction_id'));
        }
      });
      final button = iconButtonFor(tester, find.byIcon(Icons.call_end));
      await tester.runAsync(() async {
        final first = button.onPressed!.call() as Future<void>;
        final second = button.onPressed!.call() as Future<void>;
        await Future.wait([first, second]);
      });
      await tester.pumpAndSettle();

      expect(declineTxIds, hasLength(1));
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
        expect(session, isNotNull);
        addTearDown(session!.dispose);

        final declineButton = iconButtonFor(
          tester,
          find.byIcon(Icons.call_end),
        );
        await (declineButton.onPressed!.call() as Future<void>);

        expect(container.read(activeCallProvider), same(session));
        expect(observer.events.where((e) => e == 'replace'), hasLength(1));
      },
    );

    testWidgets(
      'dispose() while the decline send is still outstanding does not crash',
      (tester) async {
        await pumpShell(tester);
        pushIncomingCall(call());
        await tester.pumpAndSettle();

        final button = iconButtonFor(tester, find.byIcon(Icons.call_end));
        button.onPressed!.call();

        navigatorKey.currentState!.pop();
        await tester.pumpAndSettle();

        expect(find.byType(IncomingCallPage), findsNothing);
        expect(RingingCall.instance.callId, isNull);
        expect(tester.takeException(), isNull);
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
      expect(callsLog.has('setShowOverLockscreen', {'show': true}), isTrue);
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
        expect(session, isNotNull);
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
        expect(callsLog.has('setShowOverLockscreen', {'show': true}), isTrue);
        expect(callsLog.has('setShowOverLockscreen', {'show': false}), isFalse);
      },
    );
  });

  group('caller display', () {
    testWidgets('shows the instant fallback name on first build', (
      tester,
    ) async {
      await pumpShell(tester);
      pushIncomingCall(call());
      await tester.pump();
      expect(find.text('Bob', skipOffstage: false), findsOneWidget);
    });

    testWidgets('updates to the resolved display name once it lands', (
      tester,
    ) async {
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

    testWidgets('a known member with no displayname set also falls back to the '
        'localpart', (tester) async {
      room.setState(
        Event(
          eventId: r'$member-bob',
          type: EventTypes.RoomMember,
          stateKey: '@bob:example.org',
          senderId: '@bob:example.org',
          originServerTs: DateTime.now(),
          content: const {'membership': 'join'},
          room: room,
        ),
      );
      await pumpShell(tester);
      pushIncomingCall(call());
      await tester.pump();

      expect(find.text('Bob', skipOffstage: false), findsOneWidget);
    });

    testWidgets(
      'an unresolvable caller renders the fallback indefinitely, without '
      'crashing',
      (tester) async {
        await pumpShell(tester);
        pushIncomingCall(call());
        await tester.pumpAndSettle();

        expect(find.text('Bob'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
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

        final declineTxIds = <String?>{};
        client.onTimelineEvent.stream.listen((e) {
          if (e.messageType == callDeclineMsgtype) {
            declineTxIds.add(e.unsigned?.tryGet<String>('transaction_id'));
          }
        });
        await tester.tap(find.text('Decline'));
        await tester.pumpAndSettle();

        expect(declineTxIds, isEmpty);
        expect(find.byType(IncomingCallPage), findsOneWidget);
      },
    );
  });
}
