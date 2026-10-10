import 'dart:async';

import 'package:flutter/services.dart';

import 'caught_errors.dart';
import 'crash_reporting.dart';
import 'native_caught_error.dart';

const errorsChannel = MethodChannel('zuno/errors');

class IosDiagnostic implements Exception {
  const IosDiagnostic(this.summary);

  final String summary;

  @override
  String toString() => 'IosDiagnostic($summary)';
}

Future<void> drainNativeErrors() async {
  final List<Object?> entries;
  try {
    entries = await errorsChannel.invokeListMethod<Object?>('take') ?? const [];
  } on MissingPluginException {
    return;
  } on PlatformException catch (error, stack) {
    reportCaught('take native errors', error, stack);
    return;
  }
  for (final entry in entries.whereType<Map<Object?, Object?>>()) {
    switch (entry['kind']) {
      case 'crash':
        if (entry['summary'] case final String summary) {
          unawaited(captureCrash(IosDiagnostic(summary), null));
        }
      case 'caught':
        if (entry['label'] case final String label) {
          final origin = switch (entry['process']) {
            final String process => 'native $process',
            _ => 'native',
          };
          reportCaught('$origin: $label', NativeCaughtError.fromMap(entry));
        }
    }
  }
}
