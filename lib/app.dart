import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/calls/active_call_provider.dart';
import 'core/calls/matrixrtc/incoming_call.dart';
import 'core/calls/models/call_kind.dart';
import 'core/calls/notifications/call_notification_router.dart';
import 'core/calls/notifications/call_notification_service.dart';
import 'core/calls/notifications/ringing_call_provider.dart';
import 'core/errors/best_effort.dart';
import 'core/errors/global_error_handler.dart';
import 'core/matrix/background_sync_lifecycle.dart';
import 'core/matrix/connection_monitor.dart';
import 'core/matrix/connectivity_provider.dart';
import 'core/matrix/currently_open_room_provider.dart';
import 'core/matrix/matrix_client_provider.dart';
import 'core/matrix/room_invite.dart';
import 'core/navigation/global_navigator.dart';
import 'core/navigation/launch_route.dart';
import 'core/navigation/root_route_reset.dart';
import 'core/notifications/notification_delivery_mode.dart';
import 'core/notifications/notification_delivery_provider.dart';
import 'core/notifications/notification_permission_provider.dart';
import 'core/settings/app_preferences_provider.dart';
import 'core/share/inbound_share.dart';
import 'core/shortcuts/home_screen_shortcut.dart';
import 'core/ui/zuno_splash.dart';
import 'core/ui/zuno_theme.dart';
import 'features/settings/presentation/active_sessions_page.dart';
import 'features/auth/presentation/signed_out_entry.dart';
import 'features/calls/presentation/incoming_call_page.dart';
import 'features/chat/presentation/room_page.dart';
import 'features/rooms/presentation/room_invite_page.dart';
import 'features/rooms/presentation/room_list_page.dart';
import 'features/share/presentation/share_picker_page.dart';

const _launchBudget = Duration(seconds: 2);

class ZunoApp extends ConsumerWidget {
  final RingingCallInfo? pendingRing;

  const ZunoApp({this.pendingRing, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Zuno',
      scaffoldMessengerKey: globalScaffoldMessengerKey,
      navigatorKey: globalNavigatorKey,
      theme: zunoLightTheme,
      darkTheme: zunoDarkTheme,
      themeMode: ref.watch(themeModeProvider),
      builder: (context, child) => Column(
        children: [
          const _ConnectivityBanner(),
          Expanded(child: child ?? const SizedBox.shrink()),
        ],
      ),
      home: _AuthGate(pendingRing: pendingRing),
    );
  }
}

class _ConnectivityBanner extends ConsumerWidget {
  const _ConnectivityBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = switch (ref.watch(connectionStatusProvider).value) {
      ConnectionStatus.noInternet => 'No internet connection',
      ConnectionStatus.unreachable => 'Cannot connect right now. Trying again…',
      ConnectionStatus.online || null => null,
    };
    if (message == null) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.errorContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 18,
                color: colors.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: colors.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthGate extends ConsumerStatefulWidget {
  final RingingCallInfo? pendingRing;

  const _AuthGate({this.pendingRing});

  @override
  ConsumerState<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<_AuthGate>
    with WidgetsBindingObserver {
  StreamSubscription<String>? _shortcutSub;
  StreamSubscription<InboundShare>? _shareSub;
  StreamSubscription<String>? _messageTapSub;
  StreamSubscription<void>? _newDeviceTapSub;
  bool _checkedLaunchShare = false;
  bool _launchStarted = false;
  bool _launchHandled = false;
  bool _sawFirstResume = false;
  late final Future<void> _pendingRingShown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    bindAppStateToPushDelivery(
      currentlyOpenRoomId: () =>
          mounted ? ref.read(currentlyOpenRoomIdProvider) : null,
      isAppSyncing: _isAppSyncing,
    );
    _pendingRingShown = _showPendingRing();
    _shortcutSub = onOpenRoomShortcut.listen(_openRoomById);
    _shareSub = onInboundShare.listen(_openSharePicker);
    _messageTapSub = CallNotificationService.instance.onMessageTap.listen(
      _openRoomById,
    );
    _newDeviceTapSub = CallNotificationService.instance.onNewDeviceTap.listen(
      (_) => _openActiveSessions(),
    );
    ref.listenManual(activeCallProvider, (_, session) {
      if (session != null) return;
      _pauseSyncIfBackgrounded();
    });
    ref.listenManual(notificationDeliveryModeProvider, (_, mode) {
      _syncNotificationDelivery(
        ref.read(isLoggedInProvider).value ?? false,
        mode,
        ref.read(notificationsAllowedProvider),
      );
    });
    ref.listenManual(isLoggedInProvider, (previous, loginState) {
      if (shouldReturnToRootRoute(
        previous: previous?.value,
        next: loginState.value,
      )) {
        _returnToRootRoute();
      }
      final loggedIn = loginState.value;
      if (loggedIn == null) return;
      _syncNotificationDelivery(
        loggedIn,
        ref.read(notificationDeliveryModeProvider),
        ref.read(notificationsAllowedProvider),
      );
    });
    ref.listenManual(isOfflineProvider, (previous, next) {
      if (!becameOnline(previous, next)) return;
      final client = ref.read(matrixClientProvider);
      if (!client.isLogged()) return;
      unawaited(
        retryFailedDelivery(client, ref.read(notificationDeliveryModeProvider)),
      );
    });
    ref.listenManual(notificationsAllowedProvider, (_, allowed) {
      _syncNotificationDelivery(
        ref.read(isLoggedInProvider).value ?? false,
        ref.read(notificationDeliveryModeProvider),
        allowed,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shortcutSub?.cancel();
    _shareSub?.cancel();
    _messageTapSub?.cancel();
    _newDeviceTapSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final client = ref.read(matrixClientProvider);
    final deliveryMode = ref.read(notificationDeliveryModeProvider);
    if (client.isLogged()) {
      final inCall = ref.read(activeCallProvider) != null;
      if (shouldPauseBackgroundSync(state, deliveryMode, inCall: inCall)) {
        unawaited(client.abortSync());
      } else if (shouldResumeBackgroundSync(state, deliveryMode)) {
        client.backgroundSync = true;
      }
    }

    if (state != AppLifecycleState.resumed) return;
    if (!_sawFirstResume) {
      _sawFirstResume = true;
      return;
    }
    unawaited(() async {
      final router = ref.read(callNotificationRouterProvider.notifier);
      if (await router.recheckLaunchAction()) return;
      await router.releaseLockscreenIfIdle();
    }());
    unawaited(ref.read(notificationsAllowedProvider.notifier).refresh());
    if (client.isLogged()) {
      unawaited(recheckDelivery(client, deliveryMode));
    }
  }

  bool _isAppSyncing() {
    if (!mounted) return false;
    final client = ref.read(matrixClientProvider);
    return WidgetsBinding.instance.lifecycleState ==
            AppLifecycleState.resumed &&
        client.isLogged();
  }

  void _pauseSyncIfBackgrounded() {
    final state = WidgetsBinding.instance.lifecycleState;
    final client = ref.read(matrixClientProvider);
    if (state == null || !client.isLogged()) return;
    final deliveryMode = ref.read(notificationDeliveryModeProvider);
    if (shouldPauseBackgroundSync(state, deliveryMode, inCall: false)) {
      unawaited(client.abortSync());
    }
  }

  Future<void> _showPendingRing() async {
    final ring = widget.pendingRing;
    if (ring == null) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (RingingCall.instance.callId == ring.callId) return;
    if (ref.read(activeCallProvider) != null) return;
    final router = ref.read(callNotificationRouterProvider.notifier);
    if (await router.recheckLaunchAction(instant: true)) return;
    if (!mounted) return;
    if (RingingCall.instance.callId == ring.callId) return;
    if (ref.read(activeCallProvider) != null) return;
    final room = ref.read(matrixClientProvider).getRoomById(ring.roomId);
    if (room == null) return;
    debugPrint('zuno/push: opening ring screen for ${ring.callId}');
    Navigator.of(context).push(
      LaunchRoute(
        builder: (_) => IncomingCallPage(
          call: IncomingCall(
            room: room,
            callId: ring.callId,
            callerId: ring.callerId,
            kind: ring.isVideo ? CallKind.video : CallKind.voice,
          ),
        ),
      ),
    );
  }

  void _returnToRootRoute() {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _openActiveSessions() {
    if (!mounted) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ActiveSessionsPage()));
  }

  void _openRoomById(String roomId, {bool instant = false}) {
    final room = ref.read(matrixClientProvider).getRoomById(roomId);
    if (room == null || !mounted) return;
    Navigator.of(context).push(
      pageRoute(
        instant: instant,
        builder: (_) => isIncomingInvite(room)
            ? RoomInvitePage(room: room)
            : RoomPage(room: room),
      ),
    );
  }

  Future<InboundShare?> _takeLaunchShareOnce() async {
    if (_checkedLaunchShare) return null;
    _checkedLaunchShare = true;
    return takeLaunchShare();
  }

  void _openSharePicker(InboundShare share, {bool instant = false}) {
    if (!mounted) return;
    if (!(ref.read(isLoggedInProvider).value ?? false)) return;
    final client = ref.read(matrixClientProvider);
    Navigator.of(context).push(
      pageRoute(
        instant: instant,
        builder: (_) => SharePickerPage(
          client: client,
          destination: (room) => RoomPage(room: room, pendingShare: share),
        ),
      ),
    );
  }

  Future<void> _handleLaunch() async {
    debugPrint('zuno/push: logged in, checking launch intents');
    final router = ref.read(callNotificationRouterProvider.notifier);
    try {
      await Future.wait<void>([
        _pendingRingShown,
        _openLaunchRoom(takeLaunchRoomShortcut()),
        _openLaunchRoom(
          CallNotificationService.instance.takeLaunchRoomIdFromNotification(),
        ),
        router.handleLaunchAction(instant: true),
        _openLaunchShare(),
      ]).timeout(_launchBudget);
    } on TimeoutException {
      debugPrint('zuno/push: launch handling still running; showing chats');
    } finally {
      if (mounted) setState(() => _launchHandled = true);
    }
  }

  Future<void> _openLaunchRoom(Future<String?> pendingRoomId) async {
    final roomId = await pendingRoomId;
    if (roomId != null) _openRoomById(roomId, instant: true);
  }

  Future<void> _openLaunchShare() async {
    final share = await _takeLaunchShareOnce();
    if (share != null) _openSharePicker(share, instant: true);
  }

  void _syncNotificationDelivery(
    bool loggedIn,
    NotificationDeliveryMode mode,
    bool? notificationsAllowed,
  ) {
    if (notificationsAllowed == null) return;
    final client = ref.read(matrixClientProvider);
    for (final candidate in NotificationDeliveryMode.values) {
      final provider = notificationDeliveryProviderFor(candidate);
      if (loggedIn && notificationsAllowed && candidate == mode) {
        provider.start(client);
      } else {
        provider.stop(client);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loginState = ref.watch(isLoggedInProvider);
    final deliveryMode = ref.watch(notificationDeliveryModeProvider);
    final notificationsAllowed = ref.watch(notificationsAllowedProvider);
    return loginState.when(
      data: (loggedIn) {
        if (!loggedIn) {
          unawaited(_takeLaunchShareOnce());
        } else if (!_launchStarted) {
          _launchStarted = true;
          unawaited(_handleLaunch());
        }
        _syncNotificationDelivery(loggedIn, deliveryMode, notificationsAllowed);
        if (!loggedIn) return const SignedOutEntry();
        return _launchHandled ? const RoomListPage() : const ZunoSplash();
      },
      loading: () => const ZunoSplash(),
      error: (e, _) {
        logCaught('sign-in state', e);
        return const Scaffold(
          body: Center(
            child: Text('Zuno could not start. Close it and open it again.'),
          ),
        );
      },
    );
  }
}

class ZunoBootSplash extends StatelessWidget {
  const ZunoBootSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zuno',
      theme: zunoLightTheme,
      darkTheme: zunoDarkTheme,
      themeMode: ThemeMode.system,
      debugShowCheckedModeBanner: false,
      home: const ZunoSplash(),
    );
  }
}
