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
import 'package:zuno/core/calls/matrixrtc/resolved_call_ids_provider.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/notifications/call_notification_router.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/calls/notifications/ringing_call_provider.dart';
import 'package:zuno/core/calls/notifications/ringing_call_store.dart';
import 'package:zuno/core/errors/global_error_handler.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/navigation/global_navigator.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/features/calls/presentation/call_page.dart';
import 'package:zuno/features/calls/presentation/incoming_call_page.dart';

import '../../../helpers/fake_matrix.dart';

const _ringNotificationId = 4002;

class _PushedRoutes extends NavigatorObserver {
  final routes = <Route<Object?>>[];

  @override
  void didPush(Route<Object?> route, Route<Object?>? previousRoute) =>
      routes.add(route);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterLocalNotificationsPlatform.instance =
      AndroidFlutterLocalNotificationsPlugin();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Client client;
  late Room room;
  late SharedPreferences prefs;
  late List<MethodCall> calls;
  late List<Map<String, Object?>> activeNotifications;
  late Map<String, Object?> launchDetails;
  late _PushedRoutes pushed;

  void mock(String name, Future<Object?>? Function(MethodCall call) handle) {
    final channel = MethodChannel(name);
    messenger.setMockMethodCallHandler(channel, handle);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }

  setUp(() async {
    calls = [];
    pushed = _PushedRoutes();
    activeNotifications = [];
    launchDetails = {'notificationLaunchedApp': false};
    mock('dexterous.com/flutter/local_notifications', (call) async {
      return switch (call.method) {
        'initialize' => true,
        'getActiveNotifications' => activeNotifications,
        'getNotificationAppLaunchDetails' => launchDetails,
        _ => null,
      };
    });
    for (final name in ['zuno/calls', 'zuno/call_style']) {
      mock(name, (call) async {
        calls.add(call);
        return null;
      });
    }
    mock('flutter.baseflow.com/permissions/methods', (call) async {
      if (call.method != 'requestPermissions') return null;
      return {for (final p in (call.arguments as List).cast<int>()) p: 0};
    });
    for (final name in [
      'zuno/vibration',
      'zuno/conversations',
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
      'FlutterWebRTC.Method',
      'FlutterWebRTC.Event',
    ]) {
      mock(name, (_) async => null);
    }
    const wakelock =
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
    messenger.setMockMessageHandler(
      wakelock,
      (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );
    addTearDown(() => messenger.setMockMessageHandler(wakelock, null));

    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();

    client = buildTestClient(
      userId: '@me:example.org',
      database: SendCapableFakeDatabaseApi(),
      httpClient: MockClient(
        (request) async =>
            http.Response(jsonEncode({'event_id': r'$evt'}), 200),
      ),
    );
    client.baseUri = Uri.parse('https://example.org');
    client.bearerToken = 'test-token';
    room = buildTestRoom(client);
    client.rooms.add(room);
    RingingCall.instance.callId = null;
  });

  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    bool withNavigator = true,
  }) async {
    final container = ProviderContainer(
      overrides: [
        matrixClientProvider.overrideWithValue(client),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: withNavigator ? globalNavigatorKey : null,
          scaffoldMessengerKey: globalScaffoldMessengerKey,
          navigatorObservers: [pushed],
          home: const Scaffold(body: Text('room list')),
        ),
      ),
    );
    return container;
  }

  Future<void> pumpFor(WidgetTester tester, Duration total) async {
    const step = Duration(milliseconds: 250);
    for (var waited = Duration.zero; waited < total; waited += step) {
      await tester.pump(step);
    }
  }

  CallNotificationResponse response(
    CallNotificationAction action, {
    String callId = 'call1',
    String? roomId,
    bool isVideo = false,
  }) => CallNotificationResponse(
    action: action,
    call: (
      roomId: roomId ?? room.id,
      callId: callId,
      callerId: '@bob:example.org',
      isVideo: isVideo,
    ),
  );

  Future<void> ringOnScreen({
    String callId = 'call1',
    bool isVideo = false,
  }) async {
    await saveRingingCall(prefs, (
      roomId: room.id,
      callId: callId,
      callerId: '@bob:example.org',
      isVideo: isVideo,
    ));
    activeNotifications = [
      {
        'id': _ringNotificationId,
        'channelId': 'calls_ringing',
        'groupKey': null,
        'tag': null,
        'title': 'Incoming voice call',
        'body': 'Bob',
        'payload': null,
        'bigText': null,
      },
    ];
  }

  bool? lockscreenShown() {
    final last = calls
        .where((c) => c.method == 'setShowOverLockscreen')
        .lastOrNull;
    return (last?.arguments as Map?)?['show'] as bool?;
  }

  CallNotificationRouter router(ProviderContainer container) =>
      container.read(callNotificationRouterProvider.notifier);

  group('answering from the notification', () {
    testWidgets('opens the call screen for that call, stops the ring and '
        'hands the call to the app', (tester) async {
      final container = await pumpApp(tester);
      final handedOver = <CallSession>[];
      container.listen(activeCallProvider, (_, session) {
        if (session != null) handedOver.add(session);
      });

      await router(container)
          .handle(response(CallNotificationAction.accept, isVideo: true));
      await tester.pump();

      final session = handedOver.single;
      addTearDown(session.dispose);
      expect(session.callId, 'call1');
      expect(session.kind, CallKind.video);
      expect(session.role, CallSessionRole.callee);
      final opened = (pushed.routes.last as MaterialPageRoute<Object?>).builder(
        tester.element(find.text('room list')),
      );
      expect(opened, isA<CallPage>());
      expect((opened as CallPage).call.session, same(session));
      expect(RingingCall.instance.callId, 'call1');
      expect(calls.map((c) => c.method), contains('cancelIncomingCallStyle'));

      await pumpFor(tester, const Duration(seconds: 6));
    });

    testWidgets('while already on a call leaves that call alone', (
      tester,
    ) async {
      final container = await pumpApp(tester);
      final existing = CallSession.forIncoming(
        room: room,
        callId: 'other',
        kind: CallKind.voice,
      );
      addTearDown(existing.dispose);
      container.read(activeCallProvider.notifier).set(existing);

      await router(container).handle(response(CallNotificationAction.accept));
      await tester.pump();

      expect(container.read(activeCallProvider), same(existing));
      expect(find.byType(CallPage), findsNothing);
    });

    testWidgets('for a call already over releases the lock screen and opens '
        'nothing', (tester) async {
      final container = await pumpApp(tester);
      container.read(resolvedCallIdsProvider.notifier).markResolved('call1');

      await router(container).handle(response(CallNotificationAction.accept));
      await tester.pump();

      expect(find.byType(CallPage), findsNothing);
      expect(container.read(activeCallProvider), isNull);
      expect(lockscreenShown(), isFalse);
    });

    testWidgets('while the ring screen owns the call leaves it to that '
        'screen', (tester) async {
      final container = await pumpApp(tester);
      RingingCall.instance.set('call1');

      await router(container).handle(response(CallNotificationAction.accept));
      await tester.pump();

      expect(calls, isEmpty);
      expect(container.read(activeCallProvider), isNull);
    });

    testWidgets('for a room that never arrives says so', (tester) async {
      final container = await pumpApp(tester);

      final handling = router(container).handle(
        response(CallNotificationAction.accept, roomId: '!gone:example.org'),
      );
      await pumpFor(tester, const Duration(seconds: 11));
      await handling;
      await tester.pump();

      expect(
        find.text('Could not open that call. The room is not available.'),
        findsOneWidget,
      );
      expect(container.read(activeCallProvider), isNull);
      expect(lockscreenShown(), isFalse);
    });

    testWidgets('before the app has a navigator says so and gives the call '
        'back', (tester) async {
      final container = await pumpApp(tester, withNavigator: false);

      await router(container).handle(response(CallNotificationAction.accept));
      await tester.pump();

      expect(find.text('Could not open the call screen.'), findsOneWidget);
      expect(container.read(activeCallProvider), isNull);
      expect(RingingCall.instance.callId, isNull);
    });
  });

  group('opening the app while it rings', () {
    testWidgets('shows the ring screen for the call still ringing', (
      tester,
    ) async {
      final container = await pumpApp(tester);
      await ringOnScreen(isVideo: true);

      await router(container).handleLaunchAction();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final page = tester.widget<IncomingCallPage>(
        find.byType(IncomingCallPage),
      );
      expect(page.call.callId, 'call1');
      expect(page.call.kind, CallKind.video);
      expect(page.call.callerId, '@bob:example.org');
    });

    testWidgets('shows nothing for a ring already answered elsewhere', (
      tester,
    ) async {
      final container = await pumpApp(tester);
      await ringOnScreen();
      container.read(resolvedCallIdsProvider.notifier).markResolved('call1');

      await router(container).handleLaunchAction();
      await tester.pump();

      expect(find.byType(IncomingCallPage), findsNothing);
    });

    testWidgets('with nothing ringing releases the lock screen, and only '
        'checks once', (tester) async {
      final container = await pumpApp(tester);

      await router(container).handleLaunchAction();
      await tester.pump();
      expect(lockscreenShown(), isFalse);

      calls.clear();
      await ringOnScreen();
      await router(container).handleLaunchAction();
      await tester.pump();
      expect(find.byType(IncomingCallPage), findsNothing);
      expect(calls, isEmpty);
    });

    testWidgets('a Decline that launched the app declines without showing '
        'anything', (tester) async {
      final container = await pumpApp(tester);
      launchDetails = {
        'notificationLaunchedApp': true,
        'notificationResponse': {
          'notificationId': _ringNotificationId,
          'actionId': 'decline',
          'notificationResponseType': 1,
          'payload': jsonEncode({
            'roomId': room.id,
            'callId': 'call1',
            'callerId': '@bob:example.org',
            'isVideo': false,
          }),
        },
      };

      await tester.runAsync(() => router(container).handleLaunchAction());
      await tester.pump();

      expect(container.read(resolvedCallIdsProvider), contains('call1'));
      expect(find.byType(IncomingCallPage), findsNothing);
      expect(find.byType(CallPage), findsNothing);
    });
  });
}
