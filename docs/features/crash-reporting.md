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
| Sentry client | The global hub, including the native SDK | Its own `SentryClient`, closed after one event |

Gating feedback on the crash toggle would hide it from almost everyone, and
tapping Send is the consent. Feedback is anonymous, so there is no reply,
and the sheet says so.

## Architecture

| File (`lib/`) | Owns |
|---|---|
| `core/errors/crash_reporting.dart` | The gate, Sentry options, the install ID, enable and disable |
| `core/errors/crash_scrubber.dart` | Pure redaction of Matrix identifiers and tokens |
| `core/errors/global_error_handler.dart` | The app's error funnel (`app-foundation.md`) |
| `core/errors/feedback.dart` | `sendFeedback` and its gate |
| `features/feedback/presentation/feedback_sheet.dart` | The one-field sheet |

- **The gate** is `shouldReportCrashes`, a pure predicate over the three
  conditions, so the release-only path stays testable from a debug run.
- **Capture** comes from Sentry's own `FlutterError` and
  `PlatformDispatcher` integrations, so the app's handlers must not capture
  too, or every error is reported twice. Only the outer `runZonedGuarded` in
  `main()` captures by hand, because Sentry does not own that zone.
- **Each isolate initializes separately.** Android's two headless push
  engines start reporting with session tracking off, because a push wake is
  not a user session and would bury the crash-free rate.
- **iOS MetricKit** reports (crashes, exits, memory) are kept natively by
  `MetricsSubscriber.swift` until the app collects them at startup. They
  leave the device only under the same gate, and also feed the push
  Diagnostics hub (`notifications.md`).
- **Feedback** never touches the global hub, so it starts no native SDK,
  installs no error hooks, and behaves the same whether crash reporting is
  on or off.

## Data and privacy

- **The install ID is the only identity**: no Matrix ID, no homeserver and
  no IP. It tells one user hitting a crash many times from many users
  hitting it once. It is minted on the first opt-in, not at install, so
  someone who never opts in leaves nothing behind.
- **Everything is scrubbed** of user, room and alias IDs, event IDs, and
  tokens before it is sent.
- **Off entirely**: screenshots, view hierarchy, session replay,
  user-interaction breadcrumbs and all tracing.

## Decisions

- **Opt-in, default off.** An E2EE client must not phone home before being
  asked, and the accepted cost is that most crashes are never seen.
- **Release only**, because development crashes would swamp the project.
- **The DSN comes from `--dart-define-from-file=.env`**, a gitignored file
  with `.env.example` committed. A missing DSN disables reporting rather than
  failing the build, though CI's release build fails without one
  (`releases.md`).

## Gotchas

- **Native crashes never run `beforeSend`**, so they stay clean only because
  nothing sensitive reaches the native scope.
- **Enabling and disabling must stay serialized**, because an off-tap during
  an in-flight async init would otherwise leave reporting on.
- **A release build with reporting off leaves no trace** of an unhandled
  error, since the error snackbar is debug-only (`app-foundation.md`).
- **The event scrubber does not reach the feedback message**, so
  `sendFeedback` scrubs the text itself.
- **Send feedback is hidden without a DSN but works with crash reporting
  off**, so the toggle promises no crash reports, not no traffic.
- **Android native frames arrive R8-obfuscated**, because no mapping file is
  uploaded, and Dart frames would need a symbol upload too if builds ever
  pass `--obfuscate` or `--split-debug-info`.
- **With reporting on, release `debugPrint` stops printing**, because
  Sentry replaces it with a breadcrumb-only function, so attach any
  `debugPrint` hook after `SentryFlutter.init`.
