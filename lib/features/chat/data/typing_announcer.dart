import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart';

import '../../../core/errors/best_effort.dart';

const _typingTimeout = Duration(seconds: 20);
const _refreshInterval = Duration(seconds: 10);
const _idleTimeout = Duration(seconds: 5);

class TypingAnnouncer {
  TypingAnnouncer({
    required this.room,
    required this._input,
    required this._enabled,
  }) {
    _input.addListener(_onInputChanged);
  }

  final Room room;
  final TextEditingController _input;
  final bool Function() _enabled;
  bool _announced = false;
  Timer? _refresh;
  Timer? _idle;

  void _onInputChanged() {
    if (!_enabled()) return;
    if (_input.text.trim().isNotEmpty) {
      _start();
    } else {
      _stop();
    }
  }

  void _start() {
    _idle?.cancel();
    _idle = Timer(_idleTimeout, _stop);
    if (_announced) return;
    _announced = true;
    _announce(true);
    _refresh = Timer.periodic(_refreshInterval, (_) => _announce(true));
  }

  void _stop() {
    _idle?.cancel();
    _refresh?.cancel();
    if (!_announced) return;
    _announced = false;
    _announce(false);
  }

  void _announce(bool typing) => unawaited(
    runBestEffort(
      () => typing
          ? room.setTyping(true, timeout: _typingTimeout.inMilliseconds)
          : room.setTyping(false),
      label: 'setTyping $typing',
    ),
  );

  void dispose() {
    _input.removeListener(_onInputChanged);
    _stop();
  }
}
