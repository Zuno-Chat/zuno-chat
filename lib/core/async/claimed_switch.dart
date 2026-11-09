import 'dart:async';

import 'package:flutter/foundation.dart' show protected, visibleForTesting;

abstract class ClaimedSwitch {
  final _claims = <Object>{};

  bool get claimed => _claims.isNotEmpty;

  @protected
  Future<void> send(bool on);

  void claim(Object owner) {
    if (_claims.add(owner) && _claims.length == 1) unawaited(send(true));
  }

  void release(Object owner) {
    if (_claims.remove(owner) && _claims.isEmpty) unawaited(send(false));
  }

  @visibleForTesting
  void reset() => _claims.clear();
}
