# Crash Reporting

Unhandled errors go to Sentry only when all three hold: the user opted in
(Settings → About, off by default), the build is release, and a DSN was
compiled in. With any one missing, Sentry is never initialized.

Feedback (Settings → Send feedback) shares the DSN and the scrubber but not
the opt-in:

| | Crash reports | Feedback |
|---|---|---|
| Sent | Automatically, on the user's behalf | When the user taps Send |
| Needs | Opt-in, a release build and a DSN | A DSN only |
| Identity | A random install ID | None, not even the install ID |
| Sentry client | The global hub (`SentryFlutter.init`), including the native SDK | Its own `SentryClient`, closed after one event |

Gating feedback on the crash toggle would hide it from almost everyone, and
tapping Send is the consent. Feedback is anonymous, so there is no reply: a
contact field would hand a third party an identifier. The sheet says so.

## Architecture

| File (`lib/`) | Owns |
|---|---|
| `core/errors/crash_reporting.dart` | The gate, Sentry options, the install ID, enable and disable |
| `core/errors/crash_scrubber.dart` | Pure redaction of Matrix identifiers and tokens |
| `core/errors/global_error_handler.dart` | The app's error funnel (`app-foundation.md`) |
| `core/errors/feedback.dart` | `sendFeedback` and the `feedbackAvailable` gate |
| `features/feedback/presentation/feedback_sheet.dart` | The one-field sheet |

- **The gate** is `shouldReportCrashes`, a pure predicate over the three
  conditions, so the release-only path stays testable from a debug run.
- **Capture**: Sentry's own integrations capture `FlutterError.onError` and
  `PlatformDispatcher.onError`, so `reportUnhandledError` stays capture-free;
  hooking both would report every error twice. Only the outer
  `runZonedGuarded` in `main()` captures by hand (`reportZoneError` →
  `captureCrash`), because Sentry hooks that zone only when it owns
  `appRunner`, which it does not here. `installGlobalErrorHandlers` chains
  whatever handler it replaces, so the init order does not matter.
- **Each isolate initializes separately.** Besides the app, Android has two
  headless push engines, UnifiedPush and FCM. Both use
  `initHeadlessCrashReporting()`, which turns session tracking off: a push
  wake is not a user session, and hundreds of one-second sessions a day would
  bury the crash-free rate. The FCM engine starts it unawaited after its
  first job, so it never delays a delivery.
- **iOS MetricKit**: `MetricsSubscriber.swift`, the app's only subscriber,
  keeps crash, exit and memory reports natively (a bounded queue) until
  `RingCoordinator` takes them over `zuno/launch` at startup. Each goes to
  `captureCrash` as an `IosDiagnostic`, so it leaves the device only under
  the same gate. A kill for an unreported VoIP push reads `voip_unreported`.
  The same summaries feed the push Diagnostics hub (`notifications.md`).
- **Feedback** builds its own `SentryClient` over bare `SentryOptions`,
  sends one feedback event and closes it. It never touches the global hub,
  so it starts no native SDK, installs no error hooks, and takes the same
  path whether crash reporting is on or off. The event carries the release
  and an `os` tag. An empty `SentryId`, which the transport returns on any
  network or HTTP failure, becomes `FeedbackNotSent`.

## Data and privacy

| Key | Holds |
|---|---|
| `settings.crash_reporting` | The opt-in, default false |
| `crash_reporting.install_id` | Random 16-byte hex, minted on first opt-in |

- **The install ID is the only identity**: no Matrix ID, no homeserver and
  no IP (`sendDefaultPii` is off). It tells one user hitting a crash 40 times
  from 40 users hitting it once, without handing a third party an
  identifier. It is minted on the first opt-in, not at install, so someone
  who never opts in leaves nothing behind.
- **Everything is scrubbed.** `beforeSend` and `beforeBreadcrumb` run
  `scrubText` over user, room and alias IDs, event IDs of both forms,
  `access_token`-style parameters and bearer tokens.
- **Off entirely**: screenshots, view hierarchy, session replay,
  user-interaction breadcrumbs and all tracing.

## Decisions

- **Opt-in, default off.** An E2EE client must not phone home before being
  asked. The accepted cost is that most crashes are never seen.
- **Release only.** Development crashes would swamp the project, and the
  console already covers development.
- **The DSN comes from `--dart-define-from-file=.env`**, a gitignored file
  with `.env.example` committed. A missing DSN disables reporting rather than
  failing the build. CI's release build, however, fails without one
  (`releases.md`).

## Gotchas

- **Native crashes never run `beforeSend`**: the native SDK builds and sends
  them itself, so Dart-side scrubbing does not apply. They stay clean because
  nothing sensitive reaches the native scope: breadcrumbs are scrubbed
  before the scope syncs, and the user is set on the scope as well as in
  `beforeSend`.
- **Enabling and disabling must stay serialized.** `SentryFlutter.init` is
  async. An off-tap during an in-flight init would find `Sentry.isEnabled`
  still false, do nothing, and leave reporting on once the init lands, so
  `setCrashReportingEnabled` chains every change onto one future.
- **A release build with reporting off leaves no trace** of an unhandled
  error. The error snackbar is debug-only (`app-foundation.md`).
- **`scrubEvent` does not reach `contexts.feedback.message`**, so
  `sendFeedback` scrubs the text itself before building the event.
- **Send feedback is hidden without a DSN**, so a plain debug build never
  shows it. Feedback still sends with crash reporting off, so the toggle
  promises no crash reports, not no traffic.
- **The `os` tag is `Platform.operatingSystemVersion`.** On Android that
  may be a firmware build ID rather than a readable version;
  `device_info_plus` would fix it.
- **Android native frames arrive R8-obfuscated**, because no mapping file is
  uploaded. Dart frames stay readable only while builds pass neither
  `--obfuscate` nor `--split-debug-info`; either one needs a symbol upload
  (`sentry_dart_plugin`, not wired up).
- **With reporting on, release `debugPrint` stops printing.** Sentry's
  `DebugPrintIntegration` replaces it with a breadcrumb-only function that
  neither prints nor calls the one it replaced, so logcat goes quiet and any
  earlier `debugPrint` hook is dropped. Attach a hook after
  `SentryFlutter.init`.
