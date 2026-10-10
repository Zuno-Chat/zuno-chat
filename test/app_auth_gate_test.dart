import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unifiedpush_platform_interface/unifiedpush_platform_interface.dart';

import 'package:zuno/app.dart';
import 'package:zuno/core/calls/active_call_controller.dart';
import 'package:zuno/core/calls/active_call_provider.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/notifications/call_notification_service.dart';
import 'package:zuno/core/calls/notifications/ringing_call_provider.dart';
import 'package:zuno/core/matrix/connection_monitor.dart';
import 'package:zuno/core/matrix/connectivity_provider.dart';
import 'package:zuno/core/matrix/currently_open_room_provider.dart';
import 'package:zuno/core/matrix/homeserver.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/matrix/registration_support.dart';
import 'package:zuno/core/matrix/sign_out_wipe.dart';
import 'package:zuno/core/matrix/sync_coordinator.dart';
import 'package:zuno/core/matrix/sync_coordinator_provider.dart';
import 'package:zuno/core/matrix/sync_request_canceller.dart';
import 'package:zuno/core/navigation/global_navigator.dart';
import 'package:zuno/core/notifications/fcm_delivery_provider.dart';
import 'package:zuno/core/notifications/notification_delivery_mode.dart';
import 'package:zuno/core/notifications/notification_delivery_provider.dart';
import 'package:zuno/core/notifications/notification_permission.dart';
import 'package:zuno/core/notifications/notification_permission_provider.dart';
import 'package:zuno/core/notifications/unified_push_delivery_provider.dart';
import 'package:zuno/core/onboarding/onboarding_provider.dart';
import 'package:zuno/core/security/device_safety.dart';
import 'package:zuno/core/settings/app_preferences_provider.dart';
import 'package:zuno/core/share/inbound_share.dart';
import 'package:zuno/core/ui/zuno_splash.dart';
import 'package:zuno/features/auth/presentation/signed_out_entry.dart';
import 'package:zuno/features/calls/presentation/call_page.dart';
import 'package:zuno/features/calls/presentation/incoming_call_page.dart';
import 'package:zuno/features/chat/presentation/room_page.dart';
import 'package:zuno/features/communities/presentation/community_page.dart';
import 'package:zuno/features/rooms/presentation/room_invite_page.dart';
import 'package:zuno/features/rooms/presentation/room_list_page.dart';
import 'package:zuno/features/settings/presentation/active_sessions_page.dart';
import 'package:zuno/features/share/presentation/share_picker_page.dart';

import 'helpers/app_lifecycle.dart';
import 'helpers/call_channel_mocks.dart';
import 'helpers/fake_call_session.dart';
import 'helpers/fake_call_style_channel.dart';
import 'helpers/fake_local_notifications.dart';
import 'helpers/fake_matrix.dart';
import 'helpers/fake_unified_push.dart';
import 'helpers/fixed_homeserver.dart';

class _IdleSyncClient extends Client {
  _IdleSyncClient()
    : super(
        'test',
        database: StoredEventsFakeDatabaseApi(),
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );

  @override
  Future<void> oneShotSync({Duration? timeout}) => Completer<void>().future;
}

class _CountedHomeserver extends HomeserverNotifier {
  _CountedHomeserver(this._onCheck);

  final void Function() _onCheck;

  @override
  FutureOr<Uri> build() {
    _onCheck();
    return officialHomeserver;
  }
}

class _NotificationsAllowed extends NotificationsAllowedNotifier {
  _NotificationsAllowed(this._initial);

  final bool? _initial;
  int refreshes = 0;

  @override
  bool? build() => _initial;

  @override
  Future<bool?> refresh() async {
    refreshes++;
    return state;
  }

  void set(bool allowed) => state = allowed;
}

class _DeliveryStoppingWipe extends SignOutWipe {
  _DeliveryStoppingWipe(super.prefs);

  @override
  Future<void> onLoginState(
    bool loggedIn, {
    required Future<void> Function() stopDelivery,
  }) async {
    if (!loggedIn) await stopDelivery();
  }
}

class _RecordingUnifiedPush extends FakeUnifiedPush {
  int registrations = 0;

  @override
  Future<void> register(
    String instance,
    List<String> features,
    String? messageForDistributor,
    String? vapid,
  ) async => registrations++;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump();
  }
}

Future<void> pumpRoute(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterLocalNotificationsPlatform.instance =
      AndroidFlutterLocalNotificationsPlugin();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late _IdleSyncClient client;
  late Room room;
  late Map<String, Object?> launchDetails;
  late List<MethodCall> callsChannel;
  late List<String> backgroundService;
  late StreamController<ConnectionStatus> connection;
  late _NotificationsAllowed permission;
  String? launchShortcut;
  late Future<Object?> Function() launchShare;

  void mockChannel(
    String name,
    Future<Object?> Function(MethodCall call) handler,
  ) {
    final channel = MethodChannel(name);
    messenger.setMockMethodCallHandler(channel, handler);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }

  setUp(() {
    launchDetails = {'notificationLaunchedApp': false};
    mockChannel(
      'dexterous.com/flutter/local_notifications',
      (call) async => switch (call.method) {
        'initialize' => true,
        'getNotificationAppLaunchDetails' => launchDetails,
        'getActiveNotifications' => const <Object?>[],
        _ => null,
      },
    );
    installSilentNotificationSideChannels();
    installFakeCallStyleChannel();
    callsChannel = [];
    backgroundService = [];
    launchShortcut = null;
    launchShare = () async => null;
    mockChannel(
      'flutter.baseflow.com/permissions/methods',
      (call) async => call.method == 'checkPermissionStatus' ? 1 : null,
    );
    mockChannel('zuno/vibration', (_) async => null);
    mockChannel('com.llfbandit.record/messages', (_) async => null);
    mockChannel('zuno/calls', (call) async {
      callsChannel.add(call);
      return null;
    });
    mockChannel('zuno/background_sync', (call) async {
      if (call.method.endsWith('BackgroundSyncService')) {
        backgroundService.add(call.method);
      }
      return null;
    });
    mockChannel(
      'zuno/shortcuts',
      (call) async => call.method == 'takeLaunchRoomId' ? launchShortcut : null,
    );
    mockChannel(
      'zuno/share',
      (call) =>
          call.method == 'takeLaunchShare' ? launchShare() : Future.value(),
    );
    connection = StreamController<ConnectionStatus>();

    client = _IdleSyncClient()
      ..setUserId('@me:example.org')
      ..baseUri = Uri.parse('https://example.org')
      ..bearerToken = 'test-token';
    room = buildTestRoom(client)..partial = false;
    for (final (id, name) in [
      ('@bob:example.org', 'Bob'),
      ('@me:example.org', 'Me'),
    ]) {
      room.setState(
        User(id, membership: 'join', displayName: name, room: room),
      );
    }
    client.rooms.add(room);
  });

  tearDown(() => RingingCall.instance.callId = null);

  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    AsyncValue<bool> loggedIn = const AsyncData(true),
    Stream<bool>? loginStates,
    bool? notificationsAllowed,
    NotificationDeliveryMode? deliveryMode,
    SignOutWipe Function(SharedPreferences prefs)? signOutWipe,
    RingingCallInfo? pendingRing,
    HomeserverNotifier Function()? homeserver,
  }) async {
    SharedPreferences.setMockInitialValues({
      if (deliveryMode != null)
        'settings.notification_delivery_mode': deliveryMode.name,
    });
    final prefs = await SharedPreferences.getInstance();
    permission = _NotificationsAllowed(notificationsAllowed);
    final container = ProviderContainer(
      overrides: [
        if (loginStates != null)
          isLoggedInProvider.overrideWith((ref) => loginStates)
        else
          isLoggedInProvider.overrideWithValue(loggedIn),
        sharedPreferencesProvider.overrideWithValue(prefs),
        deviceRisksProvider.overrideWithValue(
          const AsyncValue.data(<DeviceRisk>{}),
        ),
        matrixClientProvider.overrideWithValue(client),
        syncCoordinatorProvider.overrideWith((ref) {
          final sync = SyncCoordinator(
            client,
            SyncRequestCanceller(http.Client()),
          );
          ref.onDispose(sync.dispose);
          return sync;
        }),
        connectionStatusProvider.overrideWith((ref) => connection.stream),
        onboardingStepsProvider.overrideWith((ref) async => const []),
        notificationsAllowedProvider.overrideWith(() => permission),
        if (signOutWipe != null)
          signOutWipeProvider.overrideWithValue(signOutWipe(prefs)),
        homeserverProvider.overrideWith(
          homeserver ?? () => FixedHomeserver(officialHomeserver),
        ),
        registrationSupportProvider.overrideWith(
          (ref) async =>
              const RegistrationSupport(RegistrationAvailability.disabled),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ZunoApp(pendingRing: pendingRing),
      ),
    );
    return container;
  }

  group('launch', () {
    testWidgets('a message notification that launched the app opens its chat', (
      tester,
    ) async {
      launchDetails = {
        'notificationLaunchedApp': true,
        'notificationResponse': {
          'notificationId': 1,
          'notificationResponseType': 0,
          'payload': jsonEncode({'type': 'message', 'roomId': room.id}),
        },
      };
      await pumpApp(tester);
      await settle(tester);

      expect(tester.widget<RoomPage>(find.byType(RoomPage)).room, same(room));
    });

    testWidgets('a home-screen shortcut to an invite opens the invite', (
      tester,
    ) async {
      final invite = Room(
        id: '!invite:example.org',
        client: client,
        membership: Membership.invite,
      );
      client.rooms.add(invite);
      launchShortcut = invite.id;
      await pumpApp(tester);
      await settle(tester);

      expect(find.byType(RoomInvitePage), findsOneWidget);
      expect(find.byType(RoomPage), findsNothing);
    });

    testWidgets('a launch target for a chat that is gone shows the chat list', (
      tester,
    ) async {
      launchShortcut = '!gone:example.org';
      await pumpApp(tester);
      await settle(tester);

      expect(find.byType(RoomListPage), findsOneWidget);
      expect(find.byType(RoomPage), findsNothing);
    });

    testWidgets('a launch step that hangs holds the chat list back two '
        'seconds at most', (tester) async {
      launchShare = () => Completer<Object?>().future;
      await pumpApp(tester);
      await settle(tester);

      expect(find.byType(ZunoSplash), findsOneWidget);
      expect(find.byType(RoomListPage), findsNothing);

      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(find.byType(RoomListPage), findsOneWidget);
    });

    testWidgets('a share that came in before the sign-in state was known '
        'still opens the picker', (tester) async {
      initInboundShareChannel();
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            'zuno/share',
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('share', {'text': 'early'}),
            ),
            (_) {},
          );

      await pumpApp(tester, loginStates: Stream.value(true));
      await settle(tester);
      await pumpRoute(tester);

      expect(find.byType(SharePickerPage), findsOneWidget);
    });

    testWidgets('a shared text goes to the chat picked for it', (tester) async {
      launchShare = () async => {'text': 'hello there'};
      await pumpApp(tester);
      await settle(tester);
      await pumpRoute(tester);

      await tester.tap(
        find
            .descendant(
              of: find.byType(SharePickerPage),
              matching: find.byType(ListTile),
            )
            .first,
      );
      await pumpRoute(tester);

      final page = tester.widget<RoomPage>(find.byType(RoomPage));
      expect(page.room, same(room));
      expect(page.pendingShare?.text, 'hello there');
    });
  });

  group('pending ring', () {
    RingingCallInfo ring(String roomId) => (
      roomId: roomId,
      callId: 'call1',
      callerId: '@bob:example.org',
      isVideo: false,
    );

    testWidgets('a ring that woke the app shows the ring screen', (
      tester,
    ) async {
      await pumpApp(tester, pendingRing: ring(room.id));
      await settle(tester);

      expect(find.byType(IncomingCallPage), findsOneWidget);
    });

    testWidgets('a ring for a chat the app does not know shows the chat list', (
      tester,
    ) async {
      await pumpApp(tester, pendingRing: ring('!gone:example.org'));
      await settle(tester);

      expect(find.byType(IncomingCallPage), findsNothing);
      expect(find.byType(RoomListPage), findsOneWidget);
    });
  });

  group('notification taps while running', () {
    testWidgets('a message notification opens its chat', (tester) async {
      await pumpApp(tester);
      await settle(tester);

      CallNotificationService.instance.onMessageTapForTest(room.id);
      await pumpRoute(tester);

      expect(tester.widget<RoomPage>(find.byType(RoomPage)).room, same(room));
    });

    testWidgets('a message notification during an open call takes the call '
        'screen\'s place and minimizes the call to the bar', (tester) async {
      CallChannelMocks();
      final container = await pumpApp(tester);
      await settle(tester);
      container
          .read(activeCallProvider.notifier)
          .set(FakeCallSession(room: room, kind: CallKind.voice));
      showCallScreen(
        globalNavigatorKey.currentState!,
        container.read(activeCallControllerProvider)!,
      );
      await settle(tester);
      expect(find.byType(CallPage), findsOneWidget);

      CallNotificationService.instance.onMessageTapForTest(room.id);
      await pumpRoute(tester);
      await settle(tester);

      expect(find.byType(RoomPage), findsOneWidget);
      expect(find.byType(CallPage, skipOffstage: false), findsNothing);
      expect(find.text('Return to call'), findsOneWidget);
    });

    testWidgets('a notification for a community opens the community', (
      tester,
    ) async {
      final club = buildTestRoom(client, id: '!club:example.org')
        ..partial = false;
      club.setState(
        StrippedStateEvent(
          type: EventTypes.RoomCreate,
          senderId: '@me:example.org',
          stateKey: '',
          content: {'type': 'm.space'},
        ),
      );
      client.rooms.add(club);
      await pumpApp(tester);
      await settle(tester);

      CallNotificationService.instance.onMessageTapForTest(club.id);
      await pumpRoute(tester);

      expect(
        tester.widget<CommunityPage>(find.byType(CommunityPage)).community,
        same(club),
      );
    });

    testWidgets('a message notification for a chat that is gone does nothing', (
      tester,
    ) async {
      await pumpApp(tester);
      await settle(tester);

      CallNotificationService.instance.onMessageTapForTest('!gone:example.org');
      await pumpRoute(tester);

      expect(find.byType(RoomPage), findsNothing);
      expect(find.byType(RoomListPage), findsOneWidget);
    });

    testWidgets('the new-device notification opens active sessions', (
      tester,
    ) async {
      await pumpApp(tester);
      await settle(tester);

      CallNotificationService.instance.onNewDeviceTapForTest();
      await pumpRoute(tester);

      expect(find.byType(ActiveSessionsPage), findsOneWidget);
    });
  });

  group('signing in', () {
    testWidgets('a sign-in still finishing keeps the sign-in screen', (
      tester,
    ) async {
      final logins = StreamController<bool>();
      final container = await pumpApp(tester, loginStates: logins.stream);
      logins.add(false);
      await settle(tester);
      final call = Completer<void>();
      final signIn = container
          .read(signInInFlightProvider.notifier)
          .during(() => call.future);

      logins.add(true);
      await settle(tester);
      await pumpRoute(tester);

      expect(find.byType(SignedOutEntry), findsOneWidget);
      expect(find.byType(RoomListPage), findsNothing);

      call.complete();
      await signIn;
      await settle(tester);
      await pumpRoute(tester);

      expect(find.byType(SignedOutEntry), findsNothing);
      expect(find.byType(RoomListPage), findsOneWidget);
    });
  });

  group('signing out', () {
    testWidgets('closes open screens and shows sign-in', (tester) async {
      final logins = StreamController<bool>();
      await pumpApp(tester, loginStates: logins.stream);
      logins.add(true);
      await settle(tester);
      CallNotificationService.instance.onNewDeviceTapForTest();
      await pumpRoute(tester);
      expect(find.byType(ActiveSessionsPage), findsOneWidget);

      logins.add(false);
      await settle(tester);
      await pumpRoute(tester);

      expect(find.byType(ActiveSessionsPage), findsNothing);
      expect(find.byType(SignedOutEntry), findsOneWidget);
    });

    testWidgets('checks the server again, which signing out forgets', (
      tester,
    ) async {
      var checks = 0;
      final logins = StreamController<bool>();
      await pumpApp(
        tester,
        loginStates: logins.stream,
        homeserver: () => _CountedHomeserver(() => checks++),
      );
      logins.add(false);
      await settle(tester);
      final beforeSignIn = checks;
      logins.add(true);
      await settle(tester);

      logins.add(false);
      await settle(tester);
      await pumpRoute(tester);

      expect(checks, beforeSignIn + 1);
      expect(find.byType(SignedOutEntry), findsOneWidget);
    });

    testWidgets('stops notification delivery for the wipe', (tester) async {
      final logins = StreamController<bool>();
      await pumpApp(
        tester,
        loginStates: logins.stream,
        signOutWipe: _DeliveryStoppingWipe.new,
      );
      logins.add(true);
      await settle(tester);
      expect(backgroundService, isEmpty);

      logins.add(false);
      await settle(tester);

      expect(backgroundService, contains('stopBackgroundSyncService'));
    });
  });

  group('notification delivery', () {
    testWidgets(
      'signed in with notifications allowed, the chosen mode starts',
      (tester) async {
        await pumpApp(
          tester,
          notificationsAllowed: true,
          deliveryMode: NotificationDeliveryMode.backgroundService,
        );
        await settle(tester);

        expect(backgroundService, contains('startBackgroundSyncService'));
      },
    );

    testWidgets('signed out, delivery never starts', (tester) async {
      await pumpApp(
        tester,
        loggedIn: const AsyncData(false),
        notificationsAllowed: true,
        deliveryMode: NotificationDeliveryMode.backgroundService,
      );
      await settle(tester);

      expect(backgroundService, isNot(contains('startBackgroundSyncService')));
    });

    testWidgets('turning notifications off stops delivery', (tester) async {
      await pumpApp(
        tester,
        notificationsAllowed: true,
        deliveryMode: NotificationDeliveryMode.backgroundService,
      );
      await settle(tester);
      backgroundService.clear();

      permission.set(false);
      await settle(tester);

      expect(backgroundService, isNotEmpty);
      expect(backgroundService, everyElement('stopBackgroundSyncService'));
    });

    testWidgets('switching mode stops the one left behind', (tester) async {
      fcmDeliveryProvider.notificationsAllowed = () async => false;
      addTearDown(() {
        fcmDeliveryProvider.notificationsAllowed = mayRegisterForNotifications;
        fcmDeliveryProvider.runner.liveClient = null;
      });
      final container = await pumpApp(
        tester,
        notificationsAllowed: true,
        deliveryMode: NotificationDeliveryMode.backgroundService,
      );
      await settle(tester);
      backgroundService.clear();

      await container
          .read(notificationDeliveryModeProvider.notifier)
          .set(NotificationDeliveryMode.fcm);
      await settle(tester);

      expect(backgroundService, isNotEmpty);
      expect(backgroundService, everyElement('stopBackgroundSyncService'));
    });
  });

  group('app lifecycle', () {
    testWidgets('a return to the app rechecks permission and the lock screen, '
        'the launch resume does not', (tester) async {
      await pumpApp(tester);
      await settle(tester);
      callsChannel.clear();
      final refreshesAtLaunch = permission.refreshes;

      moveLifecycleTo(tester.binding, AppLifecycleState.resumed);
      await settle(tester);

      expect(permission.refreshes, refreshesAtLaunch);
      expect(callsChannel, isEmpty);

      moveLifecycleTo(tester.binding, AppLifecycleState.paused);
      moveLifecycleTo(tester.binding, AppLifecycleState.resumed);
      await settle(tester);

      expect(permission.refreshes, refreshesAtLaunch + 1);
      expect(
        callsChannel
            .where((call) => call.method == 'setShowOverLockscreen')
            .single
            .arguments,
        {'show': false},
      );
    });

    testWidgets('a return to the app takes back the routes a Decline or a '
        'Reply from a notification reach it by', (tester) async {
      await CallNotificationService.instance.initialize();
      await pumpApp(tester);
      await settle(tester);
      final stranger = ReceivePort();
      addTearDown(stranger.close);
      for (final name in [declinePortName, messageActionPortName]) {
        IsolateNameServer.removePortNameMapping(name);
        IsolateNameServer.registerPortWithName(stranger.sendPort, name);
      }

      moveLifecycleTo(tester.binding, AppLifecycleState.paused);
      moveLifecycleTo(tester.binding, AppLifecycleState.resumed);

      expect(CallNotificationService.instance.stillHoldsDeclinePort(), isTrue);
      expect(
        IsolateNameServer.lookupPortByName(messageActionPortName),
        isNot(stranger.sendPort),
      );
    });

    testWidgets('push delivery sees the open chat and whether the app syncs', (
      tester,
    ) async {
      final container = await pumpApp(tester);
      await settle(tester);
      final runner = fcmDeliveryProvider.runner;

      moveLifecycleTo(tester.binding, AppLifecycleState.resumed);
      container.read(currentlyOpenRoomIdProvider.notifier).set(room.id);

      expect(runner.isAppSyncing(), isTrue);
      expect(runner.currentlyOpenRoomId(), room.id);

      moveLifecycleTo(tester.binding, AppLifecycleState.paused);

      expect(runner.isAppSyncing(), isFalse);
    });

    testWidgets('once the app is gone, push delivery sees no open chat', (
      tester,
    ) async {
      final container = await pumpApp(tester);
      await settle(tester);
      moveLifecycleTo(tester.binding, AppLifecycleState.resumed);
      container.read(currentlyOpenRoomIdProvider.notifier).set(room.id);

      await tester.pumpWidget(const SizedBox());

      expect(fcmDeliveryProvider.runner.currentlyOpenRoomId(), isNull);
      expect(fcmDeliveryProvider.runner.isAppSyncing(), isFalse);
    });
  });

  group('back online', () {
    late _RecordingUnifiedPush unifiedPush;

    setUp(() {
      final original = UnifiedPushPlatform.instance;
      unifiedPush = _RecordingUnifiedPush();
      UnifiedPushPlatform.instance = unifiedPush;
      unifiedPushDeliveryProvider.status.value =
          UnifiedPushStatus.registrationFailed;
      addTearDown(() {
        UnifiedPushPlatform.instance = original;
        unifiedPushDeliveryProvider.status.value = UnifiedPushStatus.idle;
        unifiedPushDeliveryProvider.runner.liveClient = null;
      });
    });

    testWidgets('retries a failed push registration', (tester) async {
      await pumpApp(tester, deliveryMode: NotificationDeliveryMode.unifiedPush);
      await settle(tester);

      connection.add(ConnectionStatus.noInternet);
      await settle(tester);
      expect(unifiedPush.registrations, 0);

      connection.add(ConnectionStatus.online);
      await settle(tester);

      expect(unifiedPush.registrations, 1);
    });

    testWidgets('signed out, retries nothing', (tester) async {
      client.bearerToken = null;
      await pumpApp(
        tester,
        loggedIn: const AsyncData(false),
        deliveryMode: NotificationDeliveryMode.unifiedPush,
      );
      await settle(tester);

      connection.add(ConnectionStatus.noInternet);
      await settle(tester);
      connection.add(ConnectionStatus.online);
      await settle(tester);

      expect(unifiedPush.registrations, 0);
    });
  });

  testWidgets('a broken sign-in state asks to reopen the app', (tester) async {
    await pumpApp(
      tester,
      loggedIn: AsyncError(StateError('store gone'), StackTrace.empty),
    );
    await tester.pump();

    expect(
      find.text('Zuno could not start. Close it and open it again.'),
      findsOneWidget,
    );
  });

  testWidgets('the boot splash shows the brand splash in the system theme', (
    tester,
  ) async {
    await tester.pumpWidget(const ZunoBootSplash());

    expect(find.byType(ZunoSplash), findsOneWidget);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
  });
}
