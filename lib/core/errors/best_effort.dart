import 'dart:async' show FutureOr;

import 'package:flutter/foundation.dart' show debugPrint;

void logCaught(String label, Object error) {
  debugPrint('zuno/caught: $label: $error');
}

Future<bool> runBestEffort(
  FutureOr<void> Function() request, {
  required String label,
}) async {
  try {
    await request();
    return true;
  } catch (error) {
    debugPrint('zuno/best-effort: $label failed, ignored: $error');
    return false;
  }
}
