import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

class SendKeepAwake {
  SendKeepAwake({
    required this.acquire,
    required this.release,
    this.grace = const Duration(milliseconds: 300),
  });

  static const tag = 'zuno_send';
  static const timeoutMs = 25000;

  final Future<void> Function(String tag, int timeoutMs) acquire;
  final Future<void> Function(String tag) release;
  final Duration grace;
  int _active = 0;
  bool _held = false;
  Timer? _idle;

  Future<T> hold<T>(Future<T> Function() work) async {
    _idle?.cancel();
    _active++;
    if (!_held) {
      _held = true;
      await acquire(tag, timeoutMs);
    }
    try {
      return await work();
    } finally {
      _active--;
      if (_active == 0) _idle = Timer(grace, _releaseIfIdle);
    }
  }

  void _releaseIfIdle() {
    if (_active > 0 || !_held) return;
    _held = false;
    unawaited(release(tag));
  }
}

const _wakeLock = MethodChannel('zuno/wake_lock');

final sendKeepAwake = SendKeepAwake(
  acquire: (tag, timeoutMs) =>
      _wakeLockCall('acquire', {'tag': tag, 'timeoutMs': timeoutMs}),
  release: (tag) => _wakeLockCall('release', {'tag': tag}),
);

Future<void> _wakeLockCall(String method, Map<String, Object> arguments) async {
  try {
    await _wakeLock.invokeMethod<void>(method, arguments);
  } catch (e) {
    debugPrint('zuno/send: background time not $method ($e)');
  }
}
