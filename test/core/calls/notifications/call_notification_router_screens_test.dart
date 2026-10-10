import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

import '../../../helpers/fake_call_style_channel.dart';
import '../../../helpers/fake_calls_channel.dart';
import '../../../helpers/fake_local_notifications.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fake_permissions.dart';
import '../../../helpers/native_method_calls.dart';

class _PushedRoutes extends NavigatorObserver {
  final routes = <Route<Object?>>[];

  @override
  void didPush(Route<Object?> route, Route<Object?>? previousRoute) =>
      routes.add(route);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Client client;
  late Room room;
  late SharedPreferences prefs;
  late RecordedMethodCalls native;
  late RecordedMethodCalls callStyle;
  late RecordedNotifications notifications;
  late _PushedRoutes pushed;

  setUp(() async {
    pushed = _PushedRoutes();
    notifications = installFakeLocalNotifications();
    native = installFakeCallsChannel();
    callStyle = installFakeCallStyleChannel();
    installFakePermissions(onRequest: permissionDenied);
    silenceMethodChannels(const [
      'zuno/vibration',
      'zuno/conversations',
      'xyz.luan/audioplayers',
      'xyz.luan/audioplayers.global',
      'FlutterWebRTC.Method',
      'FlutterWebRTC.Event',
    ]);
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
    notifications.active = [ringNotificationOnScreen()];
  }

  bool? lockscreenShown() {
    final last = native.named('setShowOverLockscreen').lastOrNull;
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
      expect(callStyle.methods, contains('cancelIncomingCallStyle'));

      await tester.pump(const Duration(seconds: 6));
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

      expect([...native.calls, ...callStyle.calls], isEmpty);
      expect(container.read(activeCallProvider), isNull);
    });

    testWidgets('for a room that never arrives says so', (tester) async {
      final container = await pumpApp(tester);

      final handling = router(container).handle(
        response(CallNotificationAction.accept, roomId: '!gone:example.org'),
      );
      await tester.pump(const Duration(seconds: 11));
      await handling;
      await tester.pump();

      expect(
        find.text('Could not open that call. The room is not available.'),
        findsOneWidget,
      );
      expect(container.read(activeCallProvider), isNull);
      expect(lockscreenShown(), isFalse);
    });

    testWidgets('before the app has a navigator says so and starts no '
        'call', (tester) async {
      final container = await pumpApp(tester, withNavigator: false);
      final started = <CallSession>[];
      container.listen(activeCallProvider, (_, session) {
        if (session != null) started.add(session);
      });

      await router(container).handle(response(CallNotificationAction.accept));
      await tester.pump();

      expect(find.text('Could not open the call screen.'), findsOneWidget);
      expect(started, isEmpty);
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

      native.clear();
      callStyle.clear();
      await ringOnScreen();
      await router(container).handleLaunchAction();
      await tester.pump();
      expect(find.byType(IncomingCallPage), findsNothing);
      expect([...native.calls, ...callStyle.calls], isEmpty);
    });

    testWidgets('a Decline that launched the app declines without showing '
        'anything', (tester) async {
      final container = await pumpApp(tester);
      notifications.launchDetails = {
        'notificationLaunchedApp': true,
        'notificationResponse': {
          'notificationId': ringNotificationId,
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
