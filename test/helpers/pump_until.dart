import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

bool shows(String text) => find.text(text).evaluate().isNotEmpty;

DateTime deviceClockNow() => DateTime.now();

Future<void> waitUntilInRealTime(
  FutureOr<bool> Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final waited = Stopwatch()..start();
  while (!await condition()) {
    if (waited.elapsed > timeout) {
      fail('Gave up after ${timeout.inSeconds} s waiting for $reason');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
  Duration step = const Duration(milliseconds: 100),
  Duration timeout = const Duration(seconds: 20),
}) async {
  final waited = Stopwatch()..start();
  while (!condition()) {
    if (waited.elapsed > timeout) {
      fail('Gave up after ${timeout.inSeconds} s waiting for $reason');
    }
    await tester.pump(step);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
}
