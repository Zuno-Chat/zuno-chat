import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../errors/best_effort.dart';
import 'notifications/call_notification_service.dart';

class ShowOverLockscreen {
  ShowOverLockscreen._();

  static final instance = ShowOverLockscreen._();

  final _claims = <Object>{};

  bool get claimed => _claims.isNotEmpty;

  void claim(Object owner) {
    if (_claims.add(owner) && _claims.length == 1) unawaited(_send(true));
  }

  void release(Object owner) {
    if (_claims.remove(owner) && _claims.isEmpty) unawaited(_send(false));
  }

  Future<void> releaseUnclaimed() async {
    if (_claims.isEmpty) await _send(false);
  }

  Future<void> _send(bool show) => runBestEffort(
    () => CallNotificationService.instance.setShowOverLockscreen(show),
    label: 'show over the lock screen',
  );

  @visibleForTesting
  void reset() => _claims.clear();
}
