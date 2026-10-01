import 'package:flutter/foundation.dart' show debugPrint;

const appStartRetryDelays = [Duration(milliseconds: 250), Duration(seconds: 1)];

enum StartupChoice { tryAgain, startOver }

Future<T> startWithRetries<T>({
  required Future<T> Function() attempt,
  Future<void> Function(Duration delay)? pause,
}) async {
  for (var tries = 0; ; tries++) {
    try {
      return await attempt();
    } catch (error) {
      if (tries == appStartRetryDelays.length) rethrow;
      debugPrint('zuno/db: start ${tries + 1} failed: $error');
      await (pause ?? Future<void>.delayed)(appStartRetryDelays[tries]);
    }
  }
}

Future<T> startClientOrAsk<T>({
  required Future<T> first,
  required Future<StartupChoice> Function(Object error) askUser,
  required Future<T> Function() retry,
  required Future<T> Function() startOver,
  void Function(Object error, StackTrace stack)? report,
}) async {
  var attempt = first;
  while (true) {
    try {
      return await attempt;
    } catch (error, stack) {
      report?.call(error, stack);
      attempt = switch (await askUser(error)) {
        StartupChoice.tryAgain => retry(),
        StartupChoice.startOver => startOver(),
      };
    }
  }
}
