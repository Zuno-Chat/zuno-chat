import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/calls/presentation/call_page.dart';
import '../../../features/calls/presentation/incoming_call_page.dart';
import '../../errors/global_error_handler.dart';
import '../../matrix/matrix_client_provider.dart';
import '../../navigation/global_navigator.dart';
import '../../navigation/launch_route.dart';
import '../../settings/app_preferences_provider.dart';
import '../active_call_provider.dart';
import '../matrixrtc/call_decline.dart';
import '../matrixrtc/call_session.dart';
import '../matrixrtc/incoming_call.dart';
import '../matrixrtc/resolved_call_ids_provider.dart';
import '../models/call_kind.dart';
import 'await_room.dart';
import 'call_notification_service.dart';
import 'pending_call_notification_action_provider.dart';
import 'ringing_call_provider.dart';

final callNotificationRouterProvider =
    NotifierProvider<CallNotificationRouter, void>(CallNotificationRouter.new);

class CallNotificationRouter extends Notifier<void> {
  bool _checkedLaunchAction = false;

  @override
  void build() {
    final sub = CallNotificationService.instance.onAction.listen(handle);
    ref.onDispose(sub.cancel);
    final hangUpSub = CallNotificationService.instance.onHangUp.listen(
      (_) => handleHangUp(),
    );
    ref.onDispose(hangUpSub.cancel);
  }

  Future<void> handleHangUp() async {
    final session = ref.read(activeCallProvider);
    if (session == null) {
      _log('hang up with no active call; nothing to end');
      return;
    }
    _log('hanging up ${session.callId} from the ongoing-call notification');
    await session.hangUp();
  }

  Future<void> handleLaunchAction({bool instant = false}) async {
    if (_checkedLaunchAction) return;
    _checkedLaunchAction = true;
    if (await recheckLaunchAction(instant: instant)) return;
    final ringing = await CallNotificationService.instance.activeRingCall();
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

    await CallNotificationService.instance.cancelIncomingCall();

    final client = ref.read(matrixClientProvider);
    final room = await awaitRoom(client, call.roomId);
    if (room == null) {
      _reportFailure('Could not open that call. The room is not available.');
      await releaseLockscreenIfIdle();
      return;
    }

    if (response.action == CallNotificationAction.decline) {
      await declineCall(room, call.callId);
      ref.read(resolvedCallIdsProvider.notifier).markResolved(call.callId);
      await releaseLockscreenIfIdle();
      return;
    }

    if (ref.read(activeCallProvider) != null) {
      _log('already on a call; ignoring accept for ${call.callId}');
      return;
    }
    if (ref.read(resolvedCallIdsProvider).contains(call.callId)) {
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
    if (await CallNotificationService.instance.activeRingCall() != null) return;
    await CallNotificationService.instance.setShowOverLockscreen(false);
  }

  void _reportFailure(String message) {
    globalScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
