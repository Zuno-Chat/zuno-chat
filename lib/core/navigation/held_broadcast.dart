import 'dart:async';

class HeldBroadcast<T extends Object> {
  T? _unheard;

  late final _controller = StreamController<T>.broadcast(onListen: _handOver);

  Stream<T> get stream => _controller.stream;

  void add(T event) {
    if (_controller.hasListener) {
      _controller.add(event);
    } else {
      _unheard = event;
    }
  }

  void _handOver() {
    final event = _unheard;
    if (event == null) return;
    _unheard = null;
    _controller.add(event);
  }
}
