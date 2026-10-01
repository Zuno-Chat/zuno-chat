import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

class SerialLock {
  final _keyed = KeyedSerialLock();

  Future<T> run<T>(Future<T> Function() action) => _keyed.run('', action);
}

class KeyedSerialLock {
  KeyedSerialLock() {
    _everyLock.add(this);
  }

  static final _everyLock = <KeyedSerialLock>[];

  @visibleForTesting
  static void forgetAllForTest() {
    for (final lock in _everyLock) {
      lock._tails.clear();
    }
  }

  final _tails = <String, Future<void>>{};

  Future<T> run<T>(String key, Future<T> Function() action) {
    final previous = _tails[key] ?? Future<void>.value();
    final done = Completer<void>();
    final tail = done.future;
    _tails[key] = tail;
    return previous.then((_) => action()).whenComplete(() {
      done.complete();
      if (identical(_tails[key], tail)) _tails.remove(key);
    });
  }
}
