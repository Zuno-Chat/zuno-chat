import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'active_call_provider.dart';
import 'matrixrtc/call_session.dart';
import 'platform/system_ring.dart';

String? waitingRing(CallSession? session, String? ringingCallId) {
  if (session == null || ringingCallId == null) return null;
  if (session.phase == CallSessionPhase.ended) return null;
  return ringingCallId == session.callId ? null : ringingCallId;
}

final callWaitingProvider = NotifierProvider<CallWaiting, String?>(
  CallWaiting.new,
);

class CallWaiting extends Notifier<String?> {
  StreamSubscription<CallSessionPhase>? _phases;

  @override
  String? build() {
    final ringing = SystemRing.instance.ringing;
    void updateLater() => scheduleMicrotask(_update);
    ringing.addListener(updateLater);
    ref.listen<CallSession?>(activeCallProvider, (_, session) {
      _follow(session);
      _update();
    });
    _follow(ref.read(activeCallProvider));
    ref.onDispose(() {
      ringing.removeListener(updateLater);
      unawaited(_phases?.cancel());
    });
    return _waiting();
  }

  void _follow(CallSession? session) {
    unawaited(_phases?.cancel());
    _phases = session?.phaseStream.listen((_) => _update());
  }

  void _update() {
    if (ref.mounted) state = _waiting();
  }

  String? _waiting() => waitingRing(
    ref.read(activeCallProvider),
    SystemRing.instance.ringing.value?.callId,
  );
}
