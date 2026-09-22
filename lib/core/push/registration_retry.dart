import 'dart:async';

const registrationRecheckInterval = Duration(hours: 6);

const _maxRetryDelay = Duration(minutes: 30);

Duration defaultRegistrationRetryDelay(int attempt) {
  final minutes = 1 << attempt.clamp(0, 5);
  final delay = Duration(minutes: minutes);
  return delay > _maxRetryDelay ? _maxRetryDelay : delay;
}

class RegistrationRetry {
  Duration Function(int attempt) delay = defaultRegistrationRetryDelay;

  Timer? _timer;
  int _attempt = 0;

  bool get scheduled => _timer != null;

  void schedule(Future<void> Function() action) {
    cancel();
    final attempt = _attempt++;
    _timer = Timer(delay(attempt), () {
      _timer = null;
      action();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void reset() {
    cancel();
    _attempt = 0;
  }
}

class RegistrationRecheck {
  DateTime Function() now = DateTime.now;

  DateTime? _last;

  void markChecked() => _last = now();

  bool claimDue() {
    final at = now();
    final last = _last;
    if (last != null && at.difference(last) < registrationRecheckInterval) {
      return false;
    }
    _last = at;
    return true;
  }
}
