import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'active_call_marker.dart';
import 'matrixrtc/call_session.dart';

final activeCallProvider = NotifierProvider<ActiveCallNotifier, CallSession?>(
  ActiveCallNotifier.new,
);

class ActiveCallNotifier extends Notifier<CallSession?> {
  @override
  CallSession? build() {
    markCallActiveInProcess(false);
    ref.onDispose(() => markCallActiveInProcess(false));
    return null;
  }

  CallSession? start(CallSession Function() create) {
    final live = state;
    if (live != null && live.phase != CallSessionPhase.ended) return null;
    final session = create();
    _hold(session);
    return session;
  }

  @visibleForTesting
  void set(CallSession? session) => _hold(session);

  void clear(CallSession session) {
    if (identical(state, session)) _hold(null);
  }

  void _hold(CallSession? session) {
    state = session;
    markCallActiveInProcess(session != null);
  }
}
