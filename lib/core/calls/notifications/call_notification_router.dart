import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/calls/presentation/call_page.dart';
import '../../../features/calls/presentation/incoming_call_page.dart';
import '../../errors/global_error_handler.dart';
import '../../matrix/matrix_client_provider.dart';
import '../../navigation/global_navigator.dart';
import '../../navigation/launch_route.dart';
import '../../platform/platform_capabilities.dart';
import '../../settings/app_preferences_provider.dart';
import '../active_call_provider.dart';
import '../matrixrtc/call_decline.dart';
import '../matrixrtc/call_session.dart';
import '../matrixrtc/incoming_call.dart';
import '../matrixrtc/resolved_call_ids_provider.dart';
import '../models/call_kind.dart';
import '../platform/incoming_call_presenter.dart';
import '../platform/system_call.dart';
import '../platform/system_ring.dart';
import '../system_call_sync.dart';
import 'await_room.dart';
import 'call_notification_service.dart';
import 'pending_call_notification_action_provider.dart';
import 'ringing_call_provider.dart';

final callNotificationRouterProvider =
    NotifierProvider<CallNotificationRouter, void>(CallNotificationRouter.new);

const _endingCallWait = Duration(seconds: 5);

class CallNotificationRouter extends Notifier<void> {
  bool _checkedLaunchAction = false;
  final _endingCallIds = <String>{};

  @override
  void build() {
    ref.watch(systemCallSyncProvider);
    final notifications = CallNotificationService.instance;
    void on<T>(Stream<T> stream, void Function(T event) onEvent) {
      final sub = stream.listen(onEvent);
      ref.onDispose(sub.cancel);
    }

    on(notifications.onAction, handle);
    on(notifications.onHangUp, handleHangUp);
    on(notifications.onRingEnded, handleRingEnded);
    on(notifications.onSystemCallFailed, (callId) {
      if (ref.read(activeCallProvider)?.callId == callId) return;
      ref.read(resolvedCallIdsProvider.notifier).markResolved(callId);
    });
    on(
      notifications.onSystemRinging,
      (call) =>
          SystemRing.instance.set(roomId: call.roomId, callId: call.callId),
    );
    if (ref.read(platformCapabilitiesProvider).callKit) {
      unawaited(notifications.takeQueuedNativeCalls());
    }
  }

  void _releaseSystemCall(RingingCallInfo call, SystemCallEnd end) {
    unawaited(
      ref
          .read(systemCallProvider)
          .end(
            roomId: call.roomId,
            callId: call.callId,
            end: end,
            byUser: false,
          ),
    );
  }

  Future<void> handleHangUp([String? callId]) async {
    final session = ref.read(activeCallProvider);
    if (callId != null && callId != session?.callId) {
      _log('hang up for $callId, not the active call; marking it over');
      ref.read(resolvedCallIdsProvider.notifier).markResolved(callId);
      return;
    }
    if (session == null) {
      _log('hang up with no active call; nothing to end');
      return;
    }
    _log('hanging up ${session.callId} from the ongoing-call notification');
    if (callId == null) {
      await session.hangUp();
      return;
    }
    _endingCallIds.add(callId);
    try {
      await session.hangUp();
    } finally {
      _endingCallIds.remove(callId);
    }
  }

  Future<void> _untilEnded(CallSession session) async {
    if (session.phase == CallSessionPhase.ended) return;
    try {
      await session.phaseStream
          .firstWhere((phase) => phase == CallSessionPhase.ended)
          .timeout(_endingCallWait);
    } catch (_) {}
  }

  Future<void> handleRingEnded(RingingCallInfo call) async {
    _log('ring ${call.callId} ended unanswered');
    ref.read(resolvedCallIdsProvider.notifier).markResolved(call.callId);
    await ref
        .read(incomingCallPresenterProvider)
        .cancelIncoming(
          roomId: call.roomId,
          callId: call.callId,
          end: RingEnd.unanswered,
        );
  }

  Future<void> handleLaunchAction({bool instant = false}) async {
    if (_checkedLaunchAction) return;
    _checkedLaunchAction = true;
    if (await recheckLaunchAction(instant: instant)) return;
    final ringing = await ref.read(incomingCallPresenterProvider).activeRing();
    _log('active ring notification: ${ringing?.callId}');
    if (ringing != null && await _showRingingScreen(ringing, instant)) return;
    await releaseLockscreenIfIdle();
  }

  Future<bool> recheckLaunchAction({bool instant = false}) async {
    final response = await CallNotificationService.instance
        .takeLaunchCallActionFromNotification();
    _log('launch action: ${response?.action}');
    if (response == null) return false;
    await handle(response, instant: instant);
    return true;
  }

  Future<bool> _showRingingScreen(RingingCallInfo ringing, bool instant) async {
    if (ref.read(activeCallProvider) != null) return true;
    if (RingingCall.instance.callId == ringing.callId) return true;
    if (ref.read(resolvedCallIdsProvider).contains(ringing.callId)) {
      _log('ring ${ringing.callId} already resolved');
      return false;
    }
    final client = ref.read(matrixClientProvider);
    final room = await awaitRoom(client, ringing.roomId);
    if (room == null) {
      _log('ring ${ringing.callId}: room ${ringing.roomId} never appeared');
      return false;
    }
    final navigator = globalNavigatorKey.currentState;
    if (navigator == null) {
      _log('ring ${ringing.callId}: no navigator yet');
      return false;
    }
    _log('showing ring screen for ${ringing.callId}');
    unawaited(
      navigator.push(
        pageRoute(
          instant: instant,
          builder: (_) => IncomingCallPage(
            call: IncomingCall(
              room: room,
              callId: ringing.callId,
              callerId: ringing.callerId,
              kind: ringing.isVideo ? CallKind.video : CallKind.voice,
            ),
          ),
        ),
      ),
    );
    return true;
  }

  Future<void> handle(
    CallNotificationResponse response, {
    bool instant = false,
  }) async {
    final call = response.call;
    _log('handling ${response.action} for ${call.callId}');
    if (RingingCall.instance.callId == call.callId) {
      _log('ring page owns ${call.callId}; leaving it to that');
      return;
    }

    final pending = ref.read(pendingCallNotificationActionProvider);
    if (pending?.call.callId == call.callId) {
      ref.read(pendingCallNotificationActionProvider.notifier).consume();
    }

    await ref
        .read(incomingCallPresenterProvider)
        .cancelIncoming(roomId: call.roomId, callId: call.callId);

    final client = ref.read(matrixClientProvider);
    final room = await awaitRoom(client, call.roomId);
    if (room == null) {
      _reportFailure('Could not open that call. The room is not available.');
      if (response.action == CallNotificationAction.accept) {
        _releaseSystemCall(call, SystemCallEnd.failed);
      }
      await releaseLockscreenIfIdle();
      return;
    }

    if (response.action == CallNotificationAction.decline) {
      await declineCall(room, call.callId);
      ref.read(resolvedCallIdsProvider.notifier).markResolved(call.callId);
      await releaseLockscreenIfIdle();
      return;
    }

    final active = ref.read(activeCallProvider);
    if (active != null && active.callId == call.callId) {
      _log('already on ${call.callId}; nothing more to accept');
      return;
    }
    if (active != null && _endingCallIds.contains(active.callId)) {
      await _untilEnded(active);
    }
    if (ref.read(activeCallProvider) != null) {
      _log('already on a call; ignoring accept for ${call.callId}');
      _releaseSystemCall(call, SystemCallEnd.failed);
      return;
    }
    if (ref.read(resolvedCallIdsProvider).contains(call.callId)) {
      _releaseSystemCall(call, SystemCallEnd.remoteEnded);
      await releaseLockscreenIfIdle();
      return;
    }

    RingingCall.instance.set(call.callId);
    final session = CallSession.forIncoming(
      room: room,
      callId: call.callId,
      kind: call.isVideo ? CallKind.video : CallKind.voice,
      lowDataMode: ref.read(lowDataCallsProvider),
    );
    ref.read(activeCallProvider.notifier).set(session);
    final navigator = globalNavigatorKey.currentState;
    if (navigator == null) {
      ref.read(activeCallProvider.notifier).set(null);
      RingingCall.instance.clear(call.callId);
      _reportFailure('Could not open the call screen.');
      return;
    }
    unawaited(
      navigator.push(
        pageRoute(
          instant: instant,
          builder: (_) => CallPage(session: session),
        ),
      ),
    );
    _log('accepted ${call.callId}, opening the call screen');
    unawaited(session.accept().catchError((_) {}));
  }

  void _log(String message) => debugPrint('zuno/call-router: $message');

  Future<void> releaseLockscreenIfIdle() async {
    if (ref.read(activeCallProvider) != null) return;
    if (RingingCall.instance.callId != null) return;
    if (await ref.read(incomingCallPresenterProvider).activeRing() != null) {
      return;
    }
    await CallNotificationService.instance.setShowOverLockscreen(false);
  }

  void _reportFailure(String message) {
    globalScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
