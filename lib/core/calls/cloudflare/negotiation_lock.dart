import 'dart:async';

class NegotiationLock {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() action) {
    final previous = _tail;
    final completer = Completer<void>();
    _tail = completer.future;
    return previous.then((_) => action()).whenComplete(completer.complete);
  }
}
