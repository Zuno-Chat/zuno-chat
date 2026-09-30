import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
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
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_provider.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/notifications/call_notification_router.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/calls/notifications/ringing_call_provider.dart';
import 'package:zuno/core/calls/platform/incoming_call_presenter.dart';
import 'package:zuno/core/calls/platform/system_ring.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';

import '../../../helpers/fake_call_style_channel.dart';
import '../../../helpers/fake_calls_channel.dart';
import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/platform_capabilities.dart';
import '../../../helpers/recording_incoming_call_presenter.dart';

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
  late SharedPreferences prefs;
  late ProviderContainer container;
  Completer<void>? teardownGate;

  ProviderContainer startRouter({
    PlatformCapabilities? capabilities,
    IncomingCallPresenter? presenter,
  }) {
    final started = ProviderContainer(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        sharedPreferencesProvider.overrideWithValue(prefs),
        if (capabilities != null)
          platformCapabilitiesProvider.overrideWithValue(capabilities),
        if (presenter != null)
          incomingCallPresenterProvider.overrideWithValue(presenter),
      ],
    );
    addTearDown(started.dispose);
    started.read(callNotificationRouterProvider);
    return started;
  }

  void restartRouterOn(
    PlatformCapabilities capabilities, {
    IncomingCallPresenter? presenter,
  }) {
    container.dispose();
    container = startRouter(capabilities: capabilities, presenter: presenter);
  }

  CallNotificationRouter router() =>
      container.read(callNotificationRouterProvider.notifier);

  Future<void> startNotificationService() async {
    messenger.setMockMethodCallHandler(notificationsChannel, (call) async {
      if (call.method == 'initialize') return true;
      return null;
    });
    await CallNotificationService.instance.initialize(claimDeclinePort: false);
  }

  CallSession startOngoingCall(String callId) {
    final session = CallSession.forIncoming(
      room: room,
      callId: callId,
      kind: CallKind.voice,
    );
    addTearDown(session.dispose);
    container.read(activeCallProvider.notifier).set(session);
    return session;
  }

  Map<String, Object?> bobsCall({String callId = 'call1'}) => {
    'roomId': room.id,
    'callId': callId,
    'callerId': '@bob:example.org',
    'isVideo': false,
  };

  CallNotificationResponse accept({String? roomId, String callId = 'call1'}) =>
      CallNotificationResponse(
        action: CallNotificationAction.accept,
        call: (
          roomId: roomId ?? room.id,
          callId: callId,
          callerId: '@bob:example.org',
          isVideo: false,
        ),
      );

  List<Object?> callIdsSent(RecordedCallsChannel toNative, String method) => [
    for (final args in toNative.argsOf(method)) (args! as Map)['callId'],
  ];

  Future<void> pumpFor(WidgetTester tester, Duration total) async {
    const step = Duration(milliseconds: 250);
    for (var waited = Duration.zero; waited < total; waited += step) {
      await tester.pump(step);
    }
  }

  void mockLaunchAction({required String action, required String callId}) {
    messenger.setMockMethodCallHandler(notificationsChannel, (call) async {
      if (call.method == 'initialize') return true;
      if (call.method != 'getNotificationAppLaunchDetails') return null;
      return <String, Object?>{
        'notificationLaunchedApp': true,
        'notificationResponse': <String, Object?>{
          'notificationId': ringNotificationId,
          'actionId': action,
          'notificationResponseType': 1,
          'payload': jsonEncode({
            'roomId': room.id,
            'callId': callId,
            'callerId': '@bob:example.org',
            'isVideo': false,
          }),
        },
      };
    });
  }

  void mockNoLaunchAction() {
    messenger.setMockMethodCallHandler(
      notificationsChannel,
      (call) async => <String, Object?>{'notificationLaunchedApp': false},
    );
  }

  setUp(() async {
    installSilentNotificationSideChannels();
    installFakeCallStyleChannel();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    RingingCall.instance.callId = null;
    teardownGate = null;

    client = buildTestClient(
      userId: '@me:example.org',
      database: SendCapableFakeDatabaseApi(),
      httpClient: MockClient((request) async {
        if (request.url.path.contains('/state/')) await teardownGate?.future;
        return http.Response(jsonEncode({'event_id': r'$evt'}), 200);
      }),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    room = buildTestRoom(client);
    client.rooms.add(room);

    container = startRouter();
  });

  tearDown(
    () => messenger.setMockMethodCallHandler(notificationsChannel, null),
  );

  test(
    'returns false and does nothing when there is no launch action',
    () async {
      mockNoLaunchAction();

      final acted = await container
          .read(callNotificationRouterProvider.notifier)
          .recheckLaunchAction();

      expect(acted, isFalse);
    },
  );

  test(
    'declines the call and marks it resolved when the launch action is Decline',
    () async {
      mockLaunchAction(action: 'decline', callId: 'call1');

      final acted = await container
          .read(callNotificationRouterProvider.notifier)
          .recheckLaunchAction();

      expect(acted, isTrue);
      expect(
        container.read(resolvedCallIdsProvider),
        contains('call1'),
        reason:
            'declineCall\'s real room.sendEvent should have gone '
            'through and the call marked resolved',
      );
    },
  );

  test(
    'calling it again for the same already-resolved call is a safe no-op',
    () async {
      mockLaunchAction(action: 'decline', callId: 'call1');
      final router = container.read(callNotificationRouterProvider.notifier);
      await router.recheckLaunchAction();

      final acted = await router.recheckLaunchAction();

      expect(acted, isTrue, reason: 'a response was still decoded...');
      expect(container.read(resolvedCallIdsProvider), {'call1'});
    },
  );

  group('ongoing-call hang up', () {
    Future<void> sendHangUpFromPlatform([String? callId]) => sendFromNative(
      'hangUpCall',
      callId == null ? null : {'callId': callId},
    );

    setUp(startNotificationService);

    test('ends the active call', () async {
      final session = startOngoingCall('ongoing1');

      await sendHangUpFromPlatform();
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.ended);
    });

    test('is a no-op when there is no active call', () async {
      container.read(activeCallProvider.notifier).set(null);

      await sendHangUpFromPlatform();
      await pumpEventQueue();

      expect(container.read(activeCallProvider), isNull);
    });

    test('a second hang up for an already-ended call is harmless', () async {
      final session = startOngoingCall('ongoing2');

      await sendHangUpFromPlatform();
      await pumpEventQueue();
      await sendHangUpFromPlatform();
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.ended);
    });

    test('ends the active call when the system names that call', () async {
      final session = startOngoingCall('ongoing1');

      await sendHangUpFromPlatform('ongoing1');
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.ended);
    });

    test('leaves the active call alone when the system names a different '
        'call, and marks that other call as over', () async {
      final session = startOngoingCall('ongoing1');

      await sendHangUpFromPlatform('stale');
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.ringing);
      expect(container.read(activeCallProvider), same(session));
      expect(container.read(resolvedCallIdsProvider), {'stale'});
    });

    test(
      'with no active call marks the call the system named as over',
      () async {
        await sendHangUpFromPlatform('call1');
        await pumpEventQueue();

        expect(container.read(resolvedCallIdsProvider), {'call1'});
        expect(container.read(activeCallProvider), isNull);
      },
    );

    test(
      'with no active call and no call named marks nothing as over',
      () async {
        await sendHangUpFromPlatform();
        await pumpEventQueue();

        expect(container.read(resolvedCallIdsProvider), isEmpty);
      },
    );
  });

  group('when CallKit reports', () {
    late RecordingIncomingCallPresenter presenter;
    late RecordedCallsChannel toNative;

    setUp(() async {
      await startNotificationService();
      toNative = installFakeCallsChannel();
      presenter = RecordingIncomingCallPresenter();
      restartRouterOn(iosCapabilities, presenter: presenter);
    });

    test('a ring it shows, that call is marked as ringing', () async {
      await sendFromNative('ringing', bobsCall());
      await pumpEventQueue();

      expect(SystemRing.instance.ringing.value, (
        roomId: room.id,
        callId: 'call1',
      ));
    });

    test('a ring that ended unanswered, the call is marked over and its ring '
        'taken down as unanswered', () async {
      await sendFromNative('ringEnded', bobsCall());
      await pumpEventQueue();

      expect(container.read(resolvedCallIdsProvider), contains('call1'));
      expect(presenter.ends, [
        (roomId: room.id, callId: 'call1', end: RingEnd.unanswered),
      ]);
    });

    test('an answer again for the call already in progress, that call is '
        'left running', () async {
      final session = startOngoingCall('call1');

      await sendFromNative('answerCall', bobsCall());
      await pumpEventQueue();

      expect(session.phase, CallSessionPhase.ringing);
      expect(container.read(activeCallProvider), same(session));
      expect(toNative.argsOf('endSystemCall'), isEmpty);
    });

    test('a system call that failed, the call is marked over, but the one in '
        'progress is left to its own teardown', () async {
      teardownGate = Completer<void>();
      startOngoingCall('ongoing1');

      await sendFromNative('callFailed', {'callId': 'stale'});
      await sendFromNative('callFailed', {'callId': 'ongoing1'});
      await pumpEventQueue();

      expect(container.read(resolvedCallIdsProvider), {'stale'});
    });
  });

  group('End & Accept on iOS', () {
    late RecordedCallsChannel toNative;

    setUp(() async {
      await startNotificationService();
      toNative = installFakeCallsChannel();
      restartRouterOn(
        iosCapabilities,
        presenter: RecordingIncomingCallPresenter(),
      );
    });

    test('ending the call in progress and answering the next starts the '
        'next', () async {
      startOngoingCall('call1');

      await sendFromNative('hangUpCall', {'callId': 'call1'});
      await sendFromNative('answerCall', bobsCall(callId: 'call2'));
      await pumpEventQueue();

      expect(callIdsSent(toNative, 'startSystemCall'), ['call1', 'call2']);
    });

    test('hanging up the answered call while the one before is still ending '
        'starts nothing and marks the answered call over', () async {
      teardownGate = Completer<void>();
      startOngoingCall('call1');

      await sendFromNative('hangUpCall', {'callId': 'call1'});
      await sendFromNative('answerCall', bobsCall(callId: 'call2'));
      await pumpEventQueue();
      await sendFromNative('hangUpCall', {'callId': 'call2'});
      await pumpEventQueue();
      teardownGate!.complete();
      await pumpEventQueue();

      expect(callIdsSent(toNative, 'startSystemCall'), ['call1']);
      expect(container.read(resolvedCallIdsProvider), contains('call2'));
    });

    test('when the call before never finishes ending, gives up after five '
        'seconds and ends the answered call as failed', () {
      teardownGate = Completer<void>();
      final ongoing = startOngoingCall('call1');

      fakeAsync((time) {
        unawaited(router().handleHangUp('call1'));
        unawaited(router().handle(accept(callId: 'call2')));
        time.elapse(const Duration(milliseconds: 4900));
        expect(toNative.argsOf('endSystemCall'), isEmpty);

        time.elapse(const Duration(milliseconds: 100));
        expect(toNative.argsOf('endSystemCall'), [
          {
            'roomId': room.id,
            'callId': 'call2',
            'reason': 'failed',
            'byUser': false,
          },
        ]);
      });
      expect(callIdsSent(toNative, 'startSystemCall'), ['call1']);
      expect(container.read(activeCallProvider), same(ongoing));
    });
  });

  group('an accept the app cannot take', () {
    const vibrationChannel = MethodChannel('zuno/vibration');
    late RecordedCallsChannel toNative;

    setUp(() async {
      messenger.setMockMethodCallHandler(vibrationChannel, (_) async => null);
      addTearDown(
        () => messenger.setMockMethodCallHandler(vibrationChannel, null),
      );
      await startNotificationService();
      toNative = installFakeCallsChannel();
    });

    group('on iOS ends the CallKit call', () {
      setUp(() => restartRouterOn(iosCapabilities));

      test('as failed while already on another call', () async {
        final ongoing = startOngoingCall('ongoing');

        await router().handle(accept());
        await pumpEventQueue();

        expect(toNative.argsOf('endSystemCall'), [
          {
            'roomId': room.id,
            'callId': 'call1',
            'reason': 'failed',
            'byUser': false,
          },
        ]);
        expect(container.read(activeCallProvider), same(ongoing));
      });

      test(
        'as ended by the other side when the call is already over',
        () async {
          container
              .read(resolvedCallIdsProvider.notifier)
              .markResolved('call1');

          await router().handle(accept());
          await pumpEventQueue();

          expect(toNative.argsOf('endSystemCall'), [
            {
              'roomId': room.id,
              'callId': 'call1',
              'reason': 'remoteEnded',
              'byUser': false,
            },
          ]);
          expect(container.read(activeCallProvider), isNull);
        },
      );

      testWidgets('as failed when the room never arrives', (tester) async {
        final handling = router().handle(accept(roomId: '!gone:example.org'));
        await pumpFor(tester, const Duration(seconds: 11));
        await handling;

        expect(toNative.argsOf('endSystemCall'), [
          {
            'roomId': '!gone:example.org',
            'callId': 'call1',
            'reason': 'failed',
            'byUser': false,
          },
        ]);
      });
    });

    group('on Android asks the system to end nothing', () {
      setUp(() => restartRouterOn(androidCapabilities));

      test('while already on another call', () async {
        final ongoing = startOngoingCall('ongoing');

        await router().handle(accept());
        await pumpEventQueue();

        expect(toNative.argsOf('endSystemCall'), isEmpty);
        expect(container.read(activeCallProvider), same(ongoing));
      });

      test('when the call is already over', () async {
        container.read(resolvedCallIdsProvider.notifier).markResolved('call1');

        await router().handle(accept());
        await pumpEventQueue();

        expect(toNative.argsOf('endSystemCall'), isEmpty);
        expect(container.read(activeCallProvider), isNull);
      });

      testWidgets('when the room never arrives', (tester) async {
        final handling = router().handle(accept(roomId: '!gone:example.org'));
        await pumpFor(tester, const Duration(seconds: 11));
        await handling;

        expect(toNative.argsOf('endSystemCall'), isEmpty);
      });
    });
  });

  group('starting the router', () {
    late RecordedCallsChannel toNative;

    setUp(() {
      toNative = installFakeCallsChannel();
    });

    test(
      'on iOS takes the events CallKit queued before Dart listened, once',
      () async {
        restartRouterOn(iosCapabilities);
        container.read(callNotificationRouterProvider);
        await pumpEventQueue();

        expect(toNative.count('takeCallEvents'), 1);
      },
    );

    test('on Android does not ask for queued call events', () async {
      restartRouterOn(androidCapabilities);
      await pumpEventQueue();

      expect(toNative.methods, isNot(contains('takeCallEvents')));
    });

    test('on iOS keeps CallKit in step with the call in progress', () async {
      restartRouterOn(iosCapabilities);

      startOngoingCall('call1');
      await pumpEventQueue();

      expect(callIdsSent(toNative, 'startSystemCall'), ['call1']);
    });

    test('on Android tells the system nothing of the call in '
        'progress', () async {
      restartRouterOn(androidCapabilities);

      startOngoingCall('call1');
      await pumpEventQueue();

      expect(toNative.methods, isNot(contains('startSystemCall')));
    });
  });
}
