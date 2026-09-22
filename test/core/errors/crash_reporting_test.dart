import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zuno/core/errors/crash_reporting.dart';

const _dsn = 'https://publickey@o0.ingest.sentry.io/1';

Future<SharedPreferences> _prefsWith(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

SentryFlutterOptions _configuredOptions({bool trackSessions = true}) {
  final options = SentryFlutterOptions();
  configureCrashReportingOptions(
    options,
    dsn: _dsn,
    installId: 'install-1',
    trackSessions: trackSessions,
  );
  return options;
}

void main() {
  group('shouldReportCrashes', () {
    test('reports when opted in, in a release build, with a DSN', () {
      expect(
        shouldReportCrashes(optedIn: true, dsn: _dsn, isReleaseBuild: true),
        isTrue,
      );
    });

    test('does not report when opted out', () {
      expect(
        shouldReportCrashes(optedIn: false, dsn: _dsn, isReleaseBuild: true),
        isFalse,
      );
    });

    test('does not report without a DSN', () {
      expect(
        shouldReportCrashes(optedIn: true, dsn: '', isReleaseBuild: true),
        isFalse,
      );
    });

    test('does not report in a debug build', () {
      expect(
        shouldReportCrashes(optedIn: true, dsn: _dsn, isReleaseBuild: false),
        isFalse,
      );
    });
  });

  group('configureCrashReportingOptions', () {
    test('sets the DSN and never sends default PII', () {
      final options = _configuredOptions();
      expect(options.dsn, _dsn);
      expect(options.sendDefaultPii, isFalse);
    });

    test('keeps every content-capturing feature off', () {
      final options = _configuredOptions();
      expect(options.attachScreenshot, isFalse);
      expect(options.enableUserInteractionBreadcrumbs, isFalse);
      expect(options.enableUserInteractionTracing, isFalse);
      expect(options.enableAutoPerformanceTracing, isFalse);
      expect(options.replay.sessionSampleRate, isNull);
      expect(options.replay.onErrorSampleRate, isNull);
      expect(options.tracesSampleRate, isNull);
    });

    test('keeps native crash handling on', () {
      expect(_configuredOptions().enableNativeCrashHandling, isTrue);
    });

    test('tracks sessions in the foreground app but not headless', () {
      expect(_configuredOptions().enableAutoSessionTracking, isTrue);
      expect(
        _configuredOptions(trackSessions: false).enableAutoSessionTracking,
        isFalse,
      );
    });

    test('scrubs an event and attaches only the install ID', () async {
      final options = _configuredOptions();
      final event = await options.beforeSend!(
        SentryEvent(message: SentryMessage('sync failed for @alice:zuno.chat')),
        Hint(),
      );

      expect(event?.message?.formatted, 'sync failed for @[redacted]');
      expect(event?.user?.id, 'install-1');
      expect(event?.user?.username, isNull);
      expect(event?.user?.email, isNull);
      expect(event?.user?.ipAddress, isNull);
    });

    test('scrubs a breadcrumb before it reaches the scope', () {
      final options = _configuredOptions();
      final crumb = options.beforeBreadcrumb!(
        Breadcrumb(message: 'opened !room:zuno.chat'),
        Hint(),
      );

      expect(crumb?.message, 'opened ![redacted]');
    });

    test('passes a null breadcrumb through untouched', () {
      final options = _configuredOptions();
      expect(options.beforeBreadcrumb!(null, Hint()), isNull);
    });
  });

  group('readOrCreateInstallId', () {
    test('creates and persists an ID when none is stored', () async {
      final prefs = await _prefsWith({});
      final id = await readOrCreateInstallId(prefs);

      expect(id, hasLength(32));
      expect(prefs.getString('crash_reporting.install_id'), id);
    });

    test('reuses a stored ID', () async {
      final prefs = await _prefsWith({'crash_reporting.install_id': 'kept'});
      expect(await readOrCreateInstallId(prefs), 'kept');
    });

    test('generates a different ID per install', () async {
      final first = await readOrCreateInstallId(await _prefsWith({}));
      final second = await readOrCreateInstallId(await _prefsWith({}));
      expect(first, isNot(second));
    });
  });

  group('readCrashReporting', () {
    test('defaults to off when unset', () async {
      expect(readCrashReporting(await _prefsWith({})), isFalse);
    });

    test('reads a previously-stored opt-in', () async {
      final prefs = await _prefsWith({'settings.crash_reporting': true});
      expect(readCrashReporting(prefs), isTrue);
    });
  });

  group('initCrashReporting', () {
    test('stays disabled when opted out', () async {
      final prefs = await _prefsWith({});
      await initCrashReporting(prefs, optedIn: false);
      expect(Sentry.isEnabled, isFalse);
    });

    test('stays disabled in a debug build even when opted in', () async {
      final prefs = await _prefsWith({});
      await initCrashReporting(prefs, optedIn: true);
      expect(Sentry.isEnabled, isFalse);
    });

    test('does not mint an install ID while opted out', () async {
      final prefs = await _prefsWith({});
      await initCrashReporting(prefs, optedIn: false);
      expect(prefs.getString('crash_reporting.install_id'), isNull);
    });
  });

  group('setCrashReportingEnabled', () {
    test(
      'applies overlapping changes in the order they were asked for',
      () async {
        final prefs = await _prefsWith({});
        final applied = <String>[];

        final on = setCrashReportingEnabled(
          prefs,
          enabled: true,
        ).then((_) => applied.add('on'));
        final off = setCrashReportingEnabled(
          prefs,
          enabled: false,
        ).then((_) => applied.add('off'));
        await Future.wait([on, off]);

        expect(applied, ['on', 'off']);
        expect(Sentry.isEnabled, isFalse);
      },
    );

    test('a failed change does not wedge the queue', () async {
      final prefs = await _prefsWith({});
      await setCrashReportingEnabled(prefs, enabled: true);
      await expectLater(
        setCrashReportingEnabled(prefs, enabled: false),
        completes,
      );
    });
  });
}
