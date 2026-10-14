import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/calls/presentation/call_page.dart';
import '../errors/best_effort.dart';
import '../errors/global_error_handler.dart';
import '../l10n/l10n.dart';
import '../navigation/global_navigator.dart';
import 'active_call_controller.dart';
import 'active_call_provider.dart';
import 'matrixrtc/call_decline.dart';
import 'matrixrtc/call_member_state.dart';
import 'matrixrtc/call_session.dart';
import 'matrixrtc/incoming_call.dart';
import 'matrixrtc/resolved_call_ids_provider.dart';
import 'matrixrtc/resolved_call_ids_store.dart';
import 'notifications/ringing_call_provider.dart';
import 'platform/incoming_call_presenter.dart';
import 'platform/system_ring.dart';

final incomingCallGateProvider = NotifierProvider<IncomingCallGate, void>(
  IncomingCallGate.new,
);

class IncomingCallGate extends Notifier<void> {
  @override
  void build() {}

  bool isSettled(String callId) =>
      RingingCall.instance.callId == callId ||
      ref.read(activeCallProvider)?.callId == callId ||
      ref.read(resolvedCallIdsProvider).contains(callId);

  Future<bool> shouldRing(
    IncomingCall call, {
    bool Function() systemRinging = _never,
  }) async {
    final callId = call.callId;
    if (isSettled(callId) || await isCallResolved(callId)) return false;
    if (isSettled(callId)) return false;
    if (answeredOnAnotherDevice(call.room, callId)) {
      ref.read(resolvedCallIdsProvider.notifier).markResolved(callId);
      unawaited(
        ref
            .read(incomingCallPresenterProvider)
            .cancelIncoming(
              roomId: call.room.id,
              callId: callId,
              end: RingEnd.answeredElsewhere,
            ),
      );
      return false;
    }
    final active = ref.read(activeCallProvider);
    if (active != null && _crossesOwnInvite(active, call)) {
      if (callId.compareTo(active.callId) < 0) {
        unawaited(_answerInsteadOf(active, call));
      }
      return false;
    }
    if (systemRinging()) return true;
    if (active != null || _anotherRings(callId)) {
      _turnAway(call);
      return false;
    }
    return true;
  }

  static bool _never() => false;

  bool _crossesOwnInvite(CallSession active, IncomingCall call) =>
      active.role == CallSessionRole.caller &&
      !active.everHadRemote &&
      active.phase != CallSessionPhase.ended &&
      active.room.id == call.room.id;

  bool _anotherRings(String callId) {
    final ringing = SystemRing.instance.ringing.value;
    return ringing != null && ringing.callId != callId;
  }

  Future<void> _answerInsteadOf(CallSession own, IncomingCall call) async {
    final ended = own.phaseStream.firstWhere(
      (phase) => phase == CallSessionPhase.ended,
    );
    unawaited(own.hangUp(summarized: true));
    try {
      await ended;
    } on StateError {
      return;
    }
    if (!ref.mounted) return;
    final session = ref.read(activeCallProvider.notifier).answer(call);
    if (session == null) return;
    final navigator = globalNavigatorKey.currentState;
    final controller = ref.read(activeCallControllerProvider);
    if (navigator != null && controller != null) {
      showCallScreen(navigator, controller);
    }
    session.accept().ignore();
  }

  void _turnAway(IncomingCall call) {
    unawaited(
      runBestEffort(
        () => declineCall(call.room, call.callId),
        label: 'decline a call while busy',
      ),
    );
    ref.read(resolvedCallIdsProvider.notifier).markResolved(call.callId);
    final callerName = call.room
        .unsafeGetUserFromMemoryOrFallback(call.callerId)
        .calcDisplayname();
    globalScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(deviceLocalizations().callsMissedCallFrom(callerName)),
      ),
    );
  }
}
