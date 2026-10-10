import 'dart:async';

import 'package:matrix/matrix.dart';

import '../errors/caught_errors.dart';

class SdkLoggedError implements Exception {
  const SdkLoggedError(this.title);

  final String title;

  @override
  String toString() => title;
}

const _titlesHandedOn = {
  'Client initialization failed',
  'Logout failed',
  'Logout all failed',
};

const _bootstrapFailure = '[Bootstrapping] Error';

bool _handedOn(String title) =>
    _titlesHandedOn.contains(title) || title.startsWith(_bootstrapFailure);

final _sdkFrame = RegExp(r'package:matrix/([^\s)]+?\.dart):(\d+)');

String? sdkCallSite(StackTrace stack) {
  for (final frame in _sdkFrame.allMatches('$stack')) {
    final file = frame[1]!;
    if (file.endsWith('/logs.dart')) continue;
    return '$file:${frame[2]}';
  }
  return null;
}

void handleSdkLogs() {
  Logs().onLog = (event) {
    Logs().outputEvents.clear();
    if (event.level.index > Level.error.index) return;
    if (_handedOn(event.title)) return;
    final site = sdkCallSite(StackTrace.current) ?? event.title;
    unawaited(
      captureCaught(
        'sdk: $site',
        event.exception ?? SdkLoggedError(event.title),
        event.stackTrace,
        detail: event.title,
      ),
    );
  };
}
