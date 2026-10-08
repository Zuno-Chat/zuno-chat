import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/best_effort.dart';
import 'active_call_provider.dart';
import 'matrixrtc/call_session.dart';

const _callEndBound = Duration(seconds: 5);

typedef EndCallsIn = Future<void> Function(Iterable<String> roomIds);

Future<void> endCall(CallSession? call) async {
  if (call == null) return;
  await runBestEffort(
    () => call.hangUp(byUser: true).timeout(_callEndBound),
    label: 'end the call',
  );
}

final endCallsInProvider = Provider<EndCallsIn>(
  (ref) => (roomIds) async {
    final call = ref.read(activeCallProvider);
    if (call == null || !roomIds.contains(call.room.id)) return;
    await endCall(call);
  },
);
