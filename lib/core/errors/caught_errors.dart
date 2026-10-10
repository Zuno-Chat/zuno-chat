import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:sentry_flutter/sentry_flutter.dart';

import 'connection_error.dart';
import 'crash_reporting.dart';

final _reportedLabels = <String>{};

class CaughtErrorType implements Exception {
  const CaughtErrorType(this.type);

  final Type type;

  @override
  String toString() => '$type';
}

void reportCaught(String label, Object error, [StackTrace? stack]) {
  debugPrint('zuno/caught: $label: $error');
  unawaited(captureCaught(label, error, stack));
}

void reportCaughtType(String label, Object error, [StackTrace? stack]) {
  debugPrint('zuno/caught: $label: ${error.runtimeType}');
  unawaited(captureCaught(label, error, stack, typeOnly: true));
}

Future<T> reportFailureOf<T>(Future<T> future, {required String label}) =>
    future.catchError((Object error, StackTrace stack) {
      reportCaught(label, error, stack);
      Error.throwWithStackTrace(error, stack);
    });

Future<void> captureCaught(
  String label,
  Object error,
  StackTrace? stack, {
  bool typeOnly = false,
  String? detail,
}) async {
  await crashReportingStarted();
  if (!Sentry.isEnabled || isConnectionError(error)) return;
  if (!_reportedLabels.add(label)) return;
  await Sentry.captureException(
    typeOnly ? CaughtErrorType(error.runtimeType) : error,
    stackTrace: stack,
    message: detail == null ? null : SentryMessage(detail),
    withScope: (scope) async {
      scope.fingerprint = [label, '${error.runtimeType}'];
      await scope.setTag('caught', label);
    },
  );
}

@visibleForTesting
void forgetReportedLabels() => _reportedLabels.clear();
