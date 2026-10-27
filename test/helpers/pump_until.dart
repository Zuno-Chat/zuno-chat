import 'dart:async';

import 'package:flutter/widgets.dart';
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

Future<ImageInfo> resolveImage(ImageProvider image) {
  final resolved = Completer<ImageInfo>();
  final stream = image.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      if (!resolved.isCompleted) resolved.complete(info);
    },
    onError: (error, stackTrace) {
      stream.removeListener(listener);
      if (!resolved.isCompleted) resolved.completeError(error, stackTrace);
    },
  );
  stream.addListener(listener);
  return resolved.future;
}

Future<ImageInfo> pumpUntilImageLoads(
  WidgetTester tester,
  ImageProvider image,
) async {
  final resolved = resolveImage(image);
  var settled = false;
  resolved.whenComplete(() => settled = true).ignore();
  await pumpUntil(tester, () => settled, reason: 'the image to load');
  await tester.pump();
  return resolved;
}
