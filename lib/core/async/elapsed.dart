import 'package:clock/clock.dart';

Stopwatch startStopwatch() =>
    (identical(clock, const Clock()) ? Stopwatch() : clock.stopwatch())
      ..start();
