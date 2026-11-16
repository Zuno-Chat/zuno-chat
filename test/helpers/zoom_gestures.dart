import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/ui/zuno_motion.dart';

Future<void> pinch(
  WidgetTester tester, {
  required List<Offset> from,
  required List<Offset> to,
}) async {
  final fingers = [for (final at in from) await tester.startGesture(at)];
  for (var step = 1; step <= 10; step++) {
    for (final (i, finger) in fingers.indexed) {
      await finger.moveTo(Offset.lerp(from[i], to[i], step / 10)!);
    }
    await tester.pump();
  }
  for (final finger in fingers) {
    await finger.up();
  }
  await tester.pump(kDoubleTapTimeout);
}

Future<void> doubleTapAt(WidgetTester tester, Offset at) async {
  await tester.tapAt(at);
  await tester.pump(kDoubleTapMinTime);
  await tester.tapAt(at);
  await tester.pump();
  await tester.pump(ZunoDurations.standard);
}

double zoomOf(WidgetTester tester, Finder finder) =>
    tester.getRect(finder).width / tester.getSize(finder).width;
