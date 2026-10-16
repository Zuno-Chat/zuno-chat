import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

class PushTiming {
  PushTiming(this.label, {int Function()? elapsedMs}) {
    _elapsed = elapsedMs ?? () => _watch.elapsedMilliseconds;
  }

  final String label;
  final _watch = Stopwatch()..start();
  late final int Function() _elapsed;
  final _marks = <(String, int)>[];

  void mark(String step) => _marks.add((step, _elapsed()));

  String report() {
    final parts = <String>[];
    var previous = 0;
    for (final (step, at) in _marks) {
      parts.add('$step=${at - previous}ms');
      previous = at;
    }
    parts.add('total=${_elapsed()}ms');
    return 'zuno/push: timing $label ${parts.join(' ')}';
  }

  void log() {
    if (kDebugMode) debugPrint(report());
  }
}
