import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'matrixrtc/call_session.dart';

final activeCallProvider = NotifierProvider<ActiveCallNotifier, CallSession?>(
  ActiveCallNotifier.new,
);

class ActiveCallNotifier extends Notifier<CallSession?> {
  @override
  CallSession? build() => null;

  void set(CallSession? session) => state = session;
}
