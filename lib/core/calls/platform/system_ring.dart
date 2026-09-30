import 'dart:async';

import 'package:flutter/foundation.dart';

typedef SystemRingingCall = ({String roomId, String callId});

class SystemRing {
  SystemRing._();
  static final instance = SystemRing._();

  static const lifetime = Duration(seconds: 60);

  final _ringing = ValueNotifier<SystemRingingCall?>(null);
  Timer? _expiry;

  ValueListenable<SystemRingingCall?> get ringing => _ringing;

  void set({required String roomId, required String callId}) {
    _expiry?.cancel();
    _expiry = Timer(lifetime, () => clear(callId));
    _ringing.value = (roomId: roomId, callId: callId);
  }

  void clear(String callId) {
    if (_ringing.value?.callId == callId) _stop();
  }

  @visibleForTesting
  void reset() => _stop();

  void _stop() {
    _expiry?.cancel();
    _expiry = null;
    _ringing.value = null;
  }
}
