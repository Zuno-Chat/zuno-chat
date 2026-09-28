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

  void set(CallSession? session) {
    state = session;
    markCallActiveInProcess(session != null);
  }
}
