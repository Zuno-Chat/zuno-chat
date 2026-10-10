import 'dart:async' show FutureOr;

import 'caught_errors.dart';

Future<bool> runBestEffort(
  FutureOr<void> Function()? request, {
  required String label,
}) async {
  if (request == null) return true;
  try {
    await request();
    return true;
  } catch (error, stack) {
    reportCaught(label, error, stack);
    return false;
  }
}
