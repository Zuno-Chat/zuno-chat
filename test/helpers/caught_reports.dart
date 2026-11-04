import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _caught = 'zuno/caught: ';

Future<List<String>> reportsDuring(Future<void> Function() body) async => [
  for (final report in await caughtDuring(body)) report.split(': ').first,
];

Future<List<String>> caughtDuring(Future<void> Function() body) async {
  final reports = <String>[];
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message == null || !message.startsWith(_caught)) return;
    reports.add(message.substring(_caught.length));
  };
  try {
    await body();
  } finally {
    debugPrint = original;
  }
  return reports;
}

List<String> recordDebugPrints() {
  final lines = <String>[];
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) lines.add(message);
  };
  addTearDown(() => debugPrint = original);
  return lines;
}
