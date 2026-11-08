import 'dart:async';

import '../../errors/backoff.dart';
import '../models/call_engine_status.dart';
import '../models/sfu_failures.dart';
import '../module/calls_module.dart';

const reconnectGrace = Duration(seconds: 5);

class DisconnectGrace {
  Timer? _timer;

  void start(void Function() onExpired) {
    _timer ??= Timer(reconnectGrace, () {
      _timer = null;
      onExpired();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}

enum ReconnectEnd {
  refused(CallEngineStatus.failed, reported: true),
  unavailable(CallEngineStatus.failed, reported: false),
  removed(CallEngineStatus.removed, reported: false);

  const ReconnectEnd(this.status, {required this.reported});

  final CallEngineStatus status;
  final bool reported;
}

ReconnectEnd? reconnectEndsOn(Object error) => switch (error) {
  CallRemovedException() => ReconnectEnd.removed,
  CallFullException() || CallsRouteGone() => ReconnectEnd.unavailable,
  SfuRefusal(permanent: true) => ReconnectEnd.refused,
  _ => null,
};

class ReconnectBudget {
  static const _attempts = 3;
  static const _baseDelay = Duration(seconds: 1);
  static const _maxDelay = Duration(seconds: 4);

  int _spent = 0;

  Duration? nextDelay() {
    if (++_spent > _attempts) return null;
    return backoffDelay(_spent, baseDelay: _baseDelay, maxDelay: _maxDelay);
  }

  void refill() => _spent = 0;
}
