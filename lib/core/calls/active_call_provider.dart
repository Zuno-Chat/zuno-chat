import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart' show Room;

import '../settings/app_preferences_provider.dart';
import 'active_call_marker.dart';
import 'matrixrtc/call_session.dart';
import 'matrixrtc/incoming_call.dart';
import 'matrixrtc/resolved_call_ids_provider.dart';
import 'models/call_kind.dart';
import 'notifications/ringing_call_provider.dart';

final activeCallProvider = NotifierProvider<ActiveCallNotifier, CallSession?>(
  ActiveCallNotifier.new,
);

class ActiveCallNotifier extends Notifier<CallSession?> {
  CallSession? _held;

  @override
  CallSession? build() {
    markCallActiveInProcess(false);
    ref.onDispose(() {
      markCallActiveInProcess(false);
      _held?.dispose();
      _held = null;
    });
    return null;
  }

  CallSession? start(CallSession Function() create) {
    final live = state;
    if (live != null && live.phase != CallSessionPhase.ended) return null;
    final session = create();
    _hold(session);
    return session;
  }

  CallSession? join({
    required Room room,
    required String callId,
    required CallKind kind,
  }) => start(
    () => CallSession.forIncoming(
      room: room,
      callId: callId,
      kind: kind,
      lowDataMode: ref.read(lowDataCallsProvider),
    ),
  );

  CallSession? answer(IncomingCall call) {
    final session = join(room: call.room, callId: call.callId, kind: call.kind);
    if (session == null) return null;
    ref.read(resolvedCallIdsProvider.notifier).markResolved(call.callId);
    RingingCall.instance.clear(call.callId);
    return session;
  }

  @visibleForTesting
  void set(CallSession? session) => _hold(session);

  void clear(CallSession session) {
    if (identical(state, session)) _hold(null);
  }

  void _hold(CallSession? session) {
    final dropped = _held;
    _held = session;
    state = session;
    markCallActiveInProcess(session != null);
    if (dropped != null && !identical(dropped, session)) dropped.dispose();
  }
}
