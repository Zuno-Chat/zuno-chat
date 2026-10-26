import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

void Function(String description, FutureOr<void> Function() body) testsOnClock(
  DateTime Function() now,
) =>
    (description, body) => test(description, () => withClock(Clock(now), body));
