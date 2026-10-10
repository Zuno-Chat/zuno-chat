import 'package:flutter_test/flutter_test.dart';

bool shows(String text) => find.text(text).evaluate().isNotEmpty;

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final waited = Stopwatch()..start();
  while (!condition()) {
    if (waited.elapsed > timeout) {
      fail('Gave up after ${timeout.inSeconds} s waiting for $reason');
    }
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
}

Future<void> pumpRealAsync(
  WidgetTester tester, {
  int rounds = 1,
  Duration step = Duration.zero,
}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(step);
  }
}
