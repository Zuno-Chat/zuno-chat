import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
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
import 'package:zuno/core/calls/matrixrtc/call_member_state.dart';
import 'package:zuno/core/calls/matrixrtc/call_session.dart';
import 'package:zuno/core/calls/matrixrtc/call_summary_message.dart';
import 'package:zuno/core/calls/matrixrtc/incoming_call_provider.dart';
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_provider.dart';
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_store.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/calls/notifications/ringing_call_provider.dart';
import 'package:zuno/core/calls/platform/system_ring.dart';
import 'package:zuno/core/calls/ring_coordinator.dart';
import 'package:zuno/core/errors/global_error_handler.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/navigation/global_navigator.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/push/read_model/read_model_publisher.dart';
import 'package:zuno/core/push/voip/launch_channel.dart';
import 'package:zuno/core/push/voip/voip_registration.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/calls/presentation/incoming_call_page.dart';

import '../../helpers/call_membership.dart';
import '../../helpers/fake_call_style_channel.dart';
import '../../helpers/fake_calls_channel.dart';
import '../../helpers/fake_local_notifications.dart';
import '../../helpers/fake_matrix.dart';
import '../../helpers/platform_capabilities.dart';
import '../../helpers/sent_call_declines.dart';

Map<String, Object?> _invite(String callId, {CallKind kind = CallKind.voice}) =>
    {
      'msgtype': callInviteMsgtype,
      'body': 'Incoming call',
      'call_id': callId,
      'kind': kind.name,
    };

http.Response _callGone(http.Request _) =>
    http.Response(jsonEncode({'errcode': 'M_NOT_FOUND', 'error': 'gone'}), 404);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterLocalNotificationsPlatform.instance =
      AndroidFlutterLocalNotificationsPlugin();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const notificationsChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );

  late Client client;
  late Room room;
  late RecordedCallsChannel native;
  late List<MethodCall> launchCalls;
  late SharedPreferences prefs;
  late http.Response Function(http.Request request) stateReply;
  Object? ringReply;

  Future<ProviderContainer> startCoordinator({
    PlatformCapabilities? capabilities,
  }) async {
    final container = ProviderContainer(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        sharedPreferencesProvider.overrideWithValue(prefs),
        platformCapabilitiesProvider.overrideWithValue(
          capabilities ?? capabilitiesLike(iosCapabilities, voipRing: true),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(ringCoordinatorProvider, (_, _) {});
    await pumpEventQueue();
    return container;
  }

  Future<void> deliver(Event event) async {
    client.onTimelineEvent.add(event);
    await pumpEventQueue();
  }

  Event invite(
    String callId, {
    String senderId = '@bob:example.org',
    CallKind kind = CallKind.voice,
  }) => buildTestEvent(
    room,
    eventId: '\$invite-$callId',
    senderId: senderId,
    content: _invite(callId, kind: kind),
  );

  Map<String, Object?> pushRing(
    String callId, {
    String source = 'push',
    bool bound = true,
  }) => {
    'uuid': 'UUID-$callId',
    if (bound) 'roomId': room.id,
    if (bound) 'callId': callId,
    'callerId': '@bob:example.org',
    'isVideo': false,
    'video': false,
    'source': source,
  };

  void startCall(
    String callId, {
    String userId = '@bob:example.org',
    String kind = 'voice',
    DateTime? at,
  }) => room.setState(
    buildTestEvent(
      room,
      eventId: '\$member-$userId-$callId',
      senderId: userId,
      stateKey: userId,
      type: callMemberEventType,
      content: {
        'memberships': [
          {
            'call_id': callId,
            'device_id': 'BOBPHONE',
            'kind': kind,
            'expires_ts': DateTime.now().millisecondsSinceEpoch + 120000,
            'created_ts': (at ?? DateTime.now()).millisecondsSinceEpoch,
            'foci_active': <String, Object?>{},
          },
        ],
      },
    ),
  );

  List<String> answeredCalls(ProviderContainer container) {
    final started = <String>[];
    container.listen(activeCallProvider, (_, session) {
      if (session != null) started.add(session.callId);
    });
    return started;
  }

  late SentCallDeclines declines;

  List<String?> declinedCallIds() => declines.watch();

  setUp(() async {
    ambientCapabilities = capabilitiesLike(iosCapabilities, voipRing: true);
    declines = SentCallDeclines();
    ringRateLimiter.clear();
    RingingCall.instance.callId = null;
    SystemRing.instance.reset();
    ringReply = 'shown';
    stateReply = (_) => http.Response(
      jsonEncode({
        'memberships': [
          {'call_id': 'call1', 'device_id': 'BOBPHONE', 'kind': 'voice'},
        ],
      }),
      200,
    );
    installSilentNotificationSideChannels();
    installFakeCallStyleChannel();
    messenger.setMockMethodCallHandler(
      notificationsChannel,
      (call) async => call.method == 'initialize' ? true : null,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(notificationsChannel, null),
    );
    native = installFakeCallsChannel(
      reply: (call) => switch (call.method) {
        'reportIncomingCall' => ringReply,
        'bindIncoming' => true,
        'startSystemCall' => <String, Object?>{'muted': false},
        _ => null,
      },
    );
    launchCalls = [];
    messenger.setMockMethodCallHandler(launchChannel, (call) async {
      launchCalls.add(call);
      return switch (call.method) {
        'takeWakeReason' => 'ring',
        'takeDiagnostics' => ['voip_unreported code=0xbaadca11'],
        _ => null,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(launchChannel, null));
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    client = buildTestClient(
      userId: '@me:example.org',
      deviceId: 'THISPHONE',
      database: SendCapableFakeDatabaseApi(),
      httpClient: MockClient((request) async {
        if (request.url.path.contains('/state/m.call.member/')) {
          return stateReply(request);
        }
        declines.record(request);
        return http.Response(jsonEncode({'event_id': r'$sent'}), 200);
      }),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    room = buildTestRoom(client);
    client.rooms.add(room);
    await CallNotificationService.instance.initialize(claimDeclinePort: false);
    native.clear();
  });

  group('rings from sync', () {
    test('a fresh invite rings through the system', () async {
      await startCoordinator();

      await deliver(invite('call1', kind: CallKind.video));

      expect(native.argsOf('reportIncomingCall'), [
        {
          'roomId': room.id,
          'callId': 'call1',
          'callerId': '@bob:example.org',
          'name': 'Empty chat',
          'isVideo': true,
        },
      ]);
      expect(SystemRing.instance.ringing.value, (
        roomId: room.id,
        callId: 'call1',
      ));
    });

    test(
      'a ring the system filtered shows nothing and declines nothing',
      () async {
        ringReply = 'filtered';
        await startCoordinator();
        final declined = declinedCallIds();

        await deliver(invite('call1'));

        expect(SystemRing.instance.ringing.value, isNull);
        expect(declined, isEmpty);
      },
    );

    testWidgets('a ring the system cannot show opens the ring screen', (
      tester,
    ) async {
      ringReply = null;
      final container = await tester.runAsync(startCoordinator);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container!,
          child: MaterialApp(
            navigatorKey: globalNavigatorKey,
            scaffoldMessengerKey: globalScaffoldMessengerKey,
            home: const SizedBox(),
          ),
        ),
      );

      await tester.runAsync(() => deliver(invite('call1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(IncomingCallPage), findsOneWidget);
    });

    testWidgets('a second call while one rings is declined and announced as '
        'missed', (tester) async {
      final container = await tester.runAsync(startCoordinator);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container!,
          child: MaterialApp(
            scaffoldMessengerKey: globalScaffoldMessengerKey,
            home: const Scaffold(),
          ),
        ),
      );
      SystemRing.instance.set(roomId: room.id, callId: 'ringing-call');
      final declined = declinedCallIds();

      await tester.runAsync(
        () => deliver(invite('call2', senderId: '@carol:example.org')),
      );
      await tester.pump();

      expect(declined, ['call2']);
      expect(container.read(resolvedCallIdsProvider), contains('call2'));
      expect(native.argsOf('reportIncomingCall'), isEmpty);
      expect(find.text('Missed call from Carol'), findsOneWidget);
      SystemRing.instance.clear('ringing-call');
    });

    test('a call already in progress declines the new one', () async {
      final container = await startCoordinator();
      final session = CallSession.forIncoming(
        room: room,
        callId: 'active',
        kind: CallKind.voice,
      );
      addTearDown(session.dispose);
      container.read(activeCallProvider.notifier).set(session);
      final declined = declinedCallIds();

      await deliver(invite('call2'));

      expect(declined, ['call2']);
      expect(native.argsOf('reportIncomingCall'), isEmpty);
    });

    test('a call my other device answered never rings', () async {
      final container = await startCoordinator();
      joinCall(
        room,
        userId: '@me:example.org',
        deviceId: 'LAPTOP',
        callId: 'call1',
      );

      await deliver(invite('call1'));

      expect(native.argsOf('reportIncomingCall'), isEmpty);
      expect(native.argsOf('endIncomingCall'), [
        {'roomId': room.id, 'callId': 'call1', 'reason': 'answeredElsewhere'},
      ]);
      expect(container.read(resolvedCallIdsProvider), contains('call1'));
    });

    test('a call another part of the app already ended never rings', () async {
      await startCoordinator();
      await markCallResolvedOnDisk(prefs, 'call1');

      await deliver(invite('call1'));

      expect(native.argsOf('reportIncomingCall'), isEmpty);
    });
  });

  group('rings native code reported', () {
    test('takes what native code queued, once, with the wake reason and its '
        'diagnostics', () async {
      await startCoordinator();

      expect(native.count('takeCallEvents'), 1);
      expect(launchCalls.map((c) => c.method), [
        'takeWakeReason',
        'takeDiagnostics',
      ]);
    });

    test('a pushed ring marks the call ringing, and its invite later only '
        'refreshes the name', () async {
      await startCoordinator();

      await sendFromNative('ringing', pushRing('call1'));
      await pumpEventQueue();
      await deliver(invite('call1', kind: CallKind.video));

      expect(SystemRing.instance.ringing.value, (
        roomId: room.id,
        callId: 'call1',
      ));
      expect(native.argsOf('reportIncomingCall'), isEmpty);
      expect(native.argsOf('updateIncoming'), [
        {
          'roomId': room.id,
          'callId': 'call1',
          'name': 'Empty chat',
          'video': true,
        },
      ]);
    });

    test('a pushed ring for a call already over is taken down', () async {
      await startCoordinator();
      await markCallResolvedOnDisk(prefs, 'call1');

      await sendFromNative('ringing', pushRing('call1'));
      await pumpEventQueue();

      expect(native.argsOf('endIncomingCall'), [
        {'roomId': room.id, 'callId': 'call1', 'reason': 'remoteEnded'},
      ]);
    });

    test('a pushed ring for a call my other device joined first ends as '
        'answered elsewhere', () async {
      final container = await startCoordinator();
      joinCall(
        room,
        userId: '@me:example.org',
        deviceId: 'LAPTOP',
        callId: 'call1',
      );

      await sendFromNative('ringing', pushRing('call1'));
      await pumpEventQueue();

      expect(native.argsOf('endIncomingCall'), [
        {'roomId': room.id, 'callId': 'call1', 'reason': 'answeredElsewhere'},
      ]);
      expect(container.read(resolvedCallIdsProvider), contains('call1'));
    });
  });

  group('a ring without its call', () {
    test('binds to the newest call that just started in a room', () async {
      startCall(
        'call0',
        userId: '@carol:example.org',
        at: DateTime.now().subtract(const Duration(seconds: 20)),
      );
      startCall('call1', kind: 'video');
      await startCoordinator();

      await sendFromNative(
        'ringing',
        pushRing('generic', source: 'generic', bound: false),
      );
      await pumpEventQueue();

      expect(native.argsOf('bindIncoming'), [
        {
          'uuid': 'UUID-generic',
          'roomId': room.id,
          'callId': 'call1',
          'callerId': '@bob:example.org',
          'name': 'Empty chat',
          'video': true,
        },
      ]);
      expect(SystemRing.instance.ringing.value?.callId, 'call1');
    });

    test(
      'binds to the next fresh invite instead of ringing it twice',
      () async {
        await startCoordinator();
        await sendFromNative(
          'ringing',
          pushRing('generic', source: 'generic', bound: false),
        );
        await pumpEventQueue();

        await deliver(invite('call7'));

        expect(native.argsOf('reportIncomingCall'), isEmpty);
        expect(
          native.argsOf('bindIncoming').map((a) => (a! as Map)['callId']),
          ['call7'],
        );
      },
    );

    test('ends when no call turns up', () {
      fakeAsync((time) {
        unawaited(startCoordinator());
        time.elapse(const Duration(seconds: 1));
        unawaited(
          sendFromNative(
            'ringing',
            pushRing('generic', source: 'generic', bound: false),
          ),
        );
        time.elapse(const Duration(seconds: 1));
        expect(native.argsOf('endUnbound'), isEmpty);

        time.elapse(genericBindWindow);

        expect(native.argsOf('endUnbound'), [
          {'uuid': 'UUID-generic'},
        ]);
      });
    });

    test('keeps its deadline when another call is marked over meanwhile', () {
      fakeAsync((time) {
        ProviderContainer? container;
        unawaited(startCoordinator().then((started) => container = started));
        time.elapse(const Duration(seconds: 1));
        unawaited(
          sendFromNative(
            'ringing',
            pushRing('generic', source: 'generic', bound: false),
          ),
        );
        time.elapse(const Duration(seconds: 1));

        container!.read(resolvedCallIdsProvider.notifier).markResolved('other');
        time.elapse(genericBindWindow);

        expect(native.argsOf('endUnbound'), [
          {'uuid': 'UUID-generic'},
        ]);
        expect(native.count('takeCallEvents'), 1);
      });
    });

    test('a call that started too long ago is not bound', () async {
      startCall('old', at: DateTime.now().subtract(const Duration(minutes: 2)));
      await startCoordinator();

      await sendFromNative(
        'ringing',
        pushRing('generic', source: 'generic', bound: false),
      );
      await pumpEventQueue();

      expect(native.argsOf('bindIncoming'), isEmpty);
    });
  });

  group('answering and declining', () {
    test('an answer for a call the caller is still in starts it, even '
        'with no screen to show it on', () async {
      final container = await startCoordinator();
      final answered = answeredCalls(container);

      await sendFromNative('answerCall', pushRing('call1'));
      await pumpEventQueue();

      expect(answered, ['call1']);
    });

    test('an answer for a call the server says is over ends it', () async {
      stateReply = _callGone;
      final container = await startCoordinator();

      final answered = answeredCalls(container);

      await sendFromNative('answerCall', pushRing('call1'));
      await pumpEventQueue();

      expect(answered, isEmpty);
      expect(native.argsOf('endSystemCall'), [
        {
          'roomId': room.id,
          'callId': 'call1',
          'reason': 'remoteEnded',
          'byUser': false,
        },
      ]);
      expect(container.read(resolvedCallIdsProvider), contains('call1'));
    });

    test('an answer for a call the server says is over frees the ring for '
        'the next call', () async {
      stateReply = _callGone;
      await startCoordinator();
      final declined = declinedCallIds();
      await sendFromNative('ringing', pushRing('call1'));
      await pumpEventQueue();
      await sendFromNative('answerCall', pushRing('call1'));
      await pumpEventQueue();

      await deliver(invite('call2'));

      expect(declined, isEmpty);
      expect(SystemRing.instance.ringing.value?.callId, 'call2');
    });

    test('an answer for a call rung from sync starts it, even before the '
        'caller shows on the server', () async {
      stateReply = _callGone;
      final container = await startCoordinator();
      final answered = answeredCalls(container);
      await deliver(invite('call1'));

      await sendFromNative('answerCall', pushRing('call1'));
      await pumpEventQueue();

      expect(answered, ['call1']);
    });

    test('a call rung from sync is asked about again once its ring is '
        'gone', () async {
      stateReply = _callGone;
      final container = await startCoordinator();
      final answered = answeredCalls(container);
      await deliver(invite('call1'));
      SystemRing.instance.clear('call1');

      await sendFromNative('answerCall', pushRing('call1'));
      await pumpEventQueue();

      expect(answered, isEmpty);
      expect(native.argsOf('endSystemCall'), hasLength(1));
    });

    test('an answer goes ahead when the server cannot be asked', () async {
      stateReply = (_) => http.Response('<html>Bad gateway</html>', 502);
      final container = await startCoordinator();

      final answered = answeredCalls(container);

      await sendFromNative('answerCall', pushRing('call1'));
      await pumpEventQueue();

      expect(answered, ['call1']);
    });

    test('a decline is sent, then native code is told it went out', () async {
      final container = await startCoordinator();
      final declined = declinedCallIds();

      await sendFromNative('declineCall', pushRing('call1'));
      await pumpEventQueue();

      expect(declined, ['call1']);
      expect(native.argsOf('declineSent'), [
        {'roomId': room.id, 'callId': 'call1'},
      ]);
      expect(container.read(resolvedCallIdsProvider), contains('call1'));
    });
  });

  group('with VoIP rings off', () {
    test(
      'nothing is taken from native code and invites are left alone',
      () async {
        await startCoordinator(
          capabilities: capabilitiesLike(iosCapabilities, voipRing: false),
        );

        await deliver(invite('call1'));

        expect(native.methods, isNot(contains('takeCallEvents')));
        expect(native.argsOf('reportIncomingCall'), isEmpty);
        expect(launchCalls, isEmpty);
      },
    );
  });

  group('starting the push ring services', () {
    test('with VoIP rings on, starts the coordinator, the read model and '
        'registration', () async {
      final container = ProviderContainer(
        overrides: [
          matrixClientProvider.overrideWithValue(client),
          sharedPreferencesProvider.overrideWithValue(prefs),
          platformCapabilitiesProvider.overrideWithValue(
            capabilitiesLike(iosCapabilities, voipRing: true),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.listen(pushRingServicesProvider, (_, _) {});

      expect(container.exists(ringCoordinatorProvider), isTrue);
      expect(container.exists(readModelPublisherProvider), isTrue);
      expect(container.exists(voipLifecycleProvider), isTrue);
    });

    test('with VoIP rings off, starts none of them', () async {
      final container = ProviderContainer(
        overrides: [
          matrixClientProvider.overrideWithValue(client),
          sharedPreferencesProvider.overrideWithValue(prefs),
          platformCapabilitiesProvider.overrideWithValue(androidCapabilities),
        ],
      );
      addTearDown(container.dispose);

      container.listen(pushRingServicesProvider, (_, _) {});

      expect(container.exists(ringCoordinatorProvider), isFalse);
      expect(container.exists(readModelPublisherProvider), isFalse);
    });
  });
}
