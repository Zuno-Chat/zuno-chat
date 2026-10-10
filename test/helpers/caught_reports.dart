import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _caught = 'zuno/caught: ';

Future<List<String>> reportsDuring(Future<void> Function() body) async {
  final labels = <String>[];
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message == null || !message.startsWith(_caught)) return;
    labels.add(message.substring(_caught.length).split(': ').first);
  };
  try {
    await body();
  } finally {
    debugPrint = original;
  }
  return labels;
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
