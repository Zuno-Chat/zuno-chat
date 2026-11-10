import 'dart:async';

import '../../async/elapsed.dart';
import '../media/call_key_slots.dart';
import 'call_sender_key_event.dart';

class CallKeySchedule {
  CallKeySchedule({
    required this.leaveDelay,
    required this.useDelay,
    required this.joinGrace,
    required this.maxAge,
    required this.onMade,
    required this.onUse,
  });

  final Duration leaveDelay;
  final Duration useDelay;
  final Duration joinGrace;
  final Duration maxAge;
  final void Function(SenderKey key) onMade;
  final void Function(int slot) onUse;

  int _epoch = 0;
  int _gen = 0;
  SenderKey? _latest;
  bool _disposed = false;
  Stopwatch? _sharedFor;
  Timer? _expiry;
  Timer? _leaveWait;
  final Set<Timer> _useWaits = {};

  SenderKey? get latest => _latest;

  SenderKey start(int epoch) {
    _cancelWaits();
    _epoch = epoch;
    _gen = 0;
    return _make();
  }

  void shared(SenderKey key) {
    if (_disposed || !identical(key, _latest) || _sharedFor != null) return;
    _sharedFor = startStopwatch();
  }

  void joined() {
    final sharedFor = _sharedFor;
    if (_disposed || sharedFor == null || sharedFor.elapsed < joinGrace) return;
    _rotateNow();
  }

  void departed({required bool removal}) {
    if (_disposed || _latest == null) return;
    if (removal) {
      _rotateNow();
      return;
    }
    _leaveWait ??= Timer(leaveDelay, () {
      _leaveWait = null;
      _rotate();
    });
  }

  void dispose() {
    _disposed = true;
    _cancelWaits();
  }

  SenderKey _make() {
    final key = (epoch: _epoch, gen: ++_gen, key: randomSenderKey());
    _latest = key;
    _sharedFor = null;
    _expiry?.cancel();
    if (!_disposed) _expiry = Timer(maxAge, _rotateNow);
    return key;
  }

  void _rotateNow() {
    _leaveWait?.cancel();
    _leaveWait = null;
    _rotate();
  }

  void _rotate() {
    final key = _make();
    onMade(key);
    late final Timer wait;
    wait = Timer(useDelay, () {
      _useWaits.remove(wait);
      onUse(senderKeySlot(key.gen));
    });
    _useWaits.add(wait);
  }

  void _cancelWaits() {
    _leaveWait?.cancel();
    _leaveWait = null;
    _expiry?.cancel();
    _expiry = null;
    for (final wait in _useWaits) {
      wait.cancel();
    }
    _useWaits.clear();
  }
}
