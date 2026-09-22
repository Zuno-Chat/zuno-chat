import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint, kReleaseMode;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'crash_scrubber.dart';

const sentryDsn = String.fromEnvironment('SENTRY_DSN');

const crashReportingKey = 'settings.crash_reporting';

const _installIdKey = 'crash_reporting.install_id';

bool readCrashReporting(SharedPreferences prefs) =>
    prefs.getBool(crashReportingKey) ?? false;

bool shouldReportCrashes({
  required bool optedIn,
  required String dsn,
  required bool isReleaseBuild,
}) => optedIn && dsn.isNotEmpty && isReleaseBuild;

void configureCrashReportingOptions(
  SentryFlutterOptions options, {
  required String dsn,
  required String installId,
  required bool trackSessions,
}) {
  options.dsn = dsn;
  options.environment = 'production';
  options.sendDefaultPii = false;
  options.enableAutoSessionTracking = trackSessions;

  options.attachScreenshot = false;
  options.enableUserInteractionBreadcrumbs = false;
  options.enableUserInteractionTracing = false;
  options.enableAutoPerformanceTracing = false;

  options.beforeSend = (event, hint) {
    final scrubbed = scrubEvent(event);
    scrubbed.user = SentryUser(id: installId);
    return scrubbed;
  };

  options.beforeBreadcrumb = (crumb, hint) =>
      crumb == null ? null : scrubBreadcrumb(crumb);
}

Future<void> initCrashReporting(
  SharedPreferences prefs, {
  required bool optedIn,
  bool trackSessions = true,
}) async {
  final allowed = shouldReportCrashes(
    optedIn: optedIn,
    dsn: sentryDsn,
    isReleaseBuild: kReleaseMode,
  );
  if (!allowed || Sentry.isEnabled) return;

  final installId = await readOrCreateInstallId(prefs);
  await SentryFlutter.init(
    (options) => configureCrashReportingOptions(
      options,
      dsn: sentryDsn,
      installId: installId,
      trackSessions: trackSessions,
    ),
  );
  Sentry.configureScope((scope) => scope.setUser(SentryUser(id: installId)));
}

Future<void> initHeadlessCrashReporting() async {
  final prefs = await SharedPreferences.getInstance();
  await initCrashReporting(
    prefs,
    optedIn: readCrashReporting(prefs),
    trackSessions: false,
  );
}

Future<void> closeCrashReporting() async {
  if (!Sentry.isEnabled) return;
  await Sentry.close();
}

Future<void> _pendingChange = Future<void>.value();

Future<void> setCrashReportingEnabled(
  SharedPreferences prefs, {
  required bool enabled,
}) {
  _pendingChange = _pendingChange
      .then(
        (_) => enabled
            ? initCrashReporting(prefs, optedIn: true)
            : closeCrashReporting(),
      )
      .catchError(
        (Object error) =>
            debugPrint('zuno/crash: switching reporting failed: $error'),
      );
  return _pendingChange;
}

Future<void> captureCrash(Object error, StackTrace? stack) async {
  if (!Sentry.isEnabled) return;
  await Sentry.captureException(error, stackTrace: stack);
}

Future<String> readOrCreateInstallId(SharedPreferences prefs) async {
  final stored = prefs.getString(_installIdKey);
  if (stored != null) return stored;

  final random = Random.secure();
  final id = List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  await prefs.setString(_installIdKey, id);
  return id;
}
