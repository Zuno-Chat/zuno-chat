# Crash Reporting

Crashes and handled errors go to Sentry only when all three hold: the user
opted in (Settings → About, off by default), the build is release, and a
DSN was compiled in. With any one missing, Sentry is never initialized.

Feedback (Settings → Send feedback) shares the DSN and the scrubber but not
the opt-in:

| | Crash and error reports | Feedback |
|---|---|---|
| Sent | Automatically, on the user's behalf | When the user taps Send |
| Needs | Opt-in, a release build and a DSN | A DSN only |
| Identity | A random install ID | None, not even the install ID |
| Sentry client | The global hub, including the native SDK | Its own `SentryClient`, closed after one event |

Gating feedback on the crash toggle would hide it from almost everyone, and
tapping Send is the consent. Feedback is anonymous, so there is no reply,
and the sheet says so.

## Architecture

| File | Owns |
|---|---|
| `lib/core/errors/crash_reporting.dart` | The gate, Sentry options, the install ID, enable and disable |
| `lib/core/errors/crash_scrubber.dart` | Pure redaction of identifiers, tokens and content |
| `lib/core/errors/global_error_handler.dart` | Unhandled errors (`app-foundation.md`) |
| `lib/core/errors/caught_errors.dart` | The funnel every handled error goes through |
| `lib/core/matrix/sdk_logs.dart` | The Matrix SDK's error logs, into the funnel |
| `lib/core/errors/native_errors.dart` | The drain of native errors and iOS MetricKit summaries |
| `CaughtErrors.kt`, `ios/Shared/CaughtErrors.swift` | The native error journal |
| `lib/core/errors/feedback.dart` | `sendFeedback` and its gate |
| `lib/features/feedback/presentation/feedback_sheet.dart` | The one-field sheet |

- **The gate** is `shouldReportCrashes`, a pure predicate over the three
  conditions, so the release-only path stays testable from a debug run.
- **Unhandled errors** come from Sentry's own `FlutterError` and
  `PlatformDispatcher` integrations, so the app's handlers must not capture
  too, or every error is reported twice. Only the outer `runZonedGuarded`
  in `main()` captures one by hand, because Sentry does not own that zone.
- **Each isolate initializes separately.** Android's two headless push
  engines start reporting with session tracking off, because a push wake is
  not a user session and would bury the crash-free rate.
- **Feedback** never touches the global hub, so it starts no native SDK,
  installs no error hooks, and behaves the same whether crash reporting is
  on or off.

### Handled errors

Every handled error reaches one funnel; plain logs (warnings, info, debug)
never do.

```
Dart catch, best-effort action ──┐
Matrix SDK error log ────────────┼─► funnel ── printed (console, breadcrumb)
native journal, drained ─────────┘     │ network failure? ─► stop
                                       │ label already sent this run? ─► stop
                                       │ reporting off? ─► stop
                                       ▼
                            Sentry, through the scrubber
```

| Rule | Why |
|---|---|
| A network failure is never sent | It is the environment, not a defect; `isConnectionError` is the one test, native network failures included (`app-foundation.md`) |
| Each label is sent once per run, and repeats stay breadcrumbs | One broken path must not flood the project; each isolate, so each push engine, counts its own run |
| A label is one fixed string per call site, never an ID | It is the tag, the repeat key and, with the error type, the group |
| An expected outcome (a user cancel, a denied permission, a 404 meaning absent, a parse fallback) narrows its catch and is not reported | A report must mean a defect |
| An error whose text can carry a location or message content is sent as its type only | The scrubber cannot recognize every shape of either (`location-sharing.md`) |
| An error native code hands to Dart is reported only by Dart | Otherwise it is sent twice |

- **Matrix SDK logs** at `error` and `wtf` are reported, labelled by the
  SDK file and line that logged them, since log titles interpolate IDs. A
  title the SDK also hands on to Zuno (a failed client start, logout or
  bootstrap) is skipped, because Zuno reports what it receives. The hook is
  installed with every client, so every isolate that starts one reports.
- **Native errors** (Kotlin and Swift catches) go into an on-device
  journal, which the app drains over `zuno/errors` at startup and on every
  resume, in the main app only. iOS MetricKit summaries (crashes, exits,
  memory) ride the same drain as crashes and still feed the push
  Diagnostics hub (`notifications.md`).
  - The journal is bounded, keeps one entry per label until drained, and
    is written whatever the opt-in says; the drain drops it when reporting
    is off.
  - Android keeps one journal, since all Kotlin runs in the app's one
    process.
  - iOS keeps one file per entry, created exclusively and named by process
    and label, so the app and its two extensions never write the same file.
    No App Group spans all three processes, so the app drains both groups.
  - Kotlin entries carry the top stack frames; Swift errors carry none.
- **A report waits, bounded, for a crash-reporting start already under
  way**, because the FCM push engine starts reporting alongside its first
  push instead of delaying it, and that push's errors would otherwise be
  lost.

## Data and privacy

- **The install ID is the only identity**: no Matrix ID, no homeserver and
  no IP. It tells one user hitting a crash many times from many users
  hitting it once. It is minted on the first opt-in, not at install, so
  someone who never opts in leaves nothing behind.
- **Everything is scrubbed before it is sent**: messages, exception values
  and their mechanism data, breadcrumbs (first line only), tags and the
  fingerprint.

  | Redacted | Why |
  |---|---|
  | User, room (with or without a server name) and alias IDs, event IDs, tokens | Identity and access |
  | JSON objects | SDK error logs can carry event content |
  | `geo:` URIs | Locations |
  | URL hosts | An iOS network error names the homeserver |
  | Device file paths and Apple's “quoted” file names | They can name what the user shared |
  | A `FormatException` past its first line | The rest is the text it failed to parse |

- **Native entries stay on the device** until the funnel sends or drops
  them, so they get the same gate, scrubber and network filter as Dart's.
- **Off entirely**: screenshots, view hierarchy, session replay,
  user-interaction breadcrumbs and all tracing.

## Decisions

- **Opt-in, default off.** An E2EE client must not phone home before being
  asked, and the accepted cost is that most crashes and errors are never
  seen.
- **One toggle, "Send crash and error reports"**, because a toggle must name
  everything it sends.
- **Native errors go through the Dart funnel, not native Sentry capture.**
  One owner then holds the gate, the scrubber, the network filter and the
  repeat limit, the extensions and native code that runs before Flutter
  starts Sentry are covered, and native symbols are not uploaded anyway.
- **Release only**, because development crashes would swamp the project.
- **The DSN comes from `--dart-define-from-file=.env`**, a gitignored file
  with `.env.example` committed. A missing DSN disables reporting rather than
  failing the build, though CI's release build fails without one
  (`releases.md`).

## Gotchas

- **Crashes caught by Sentry's native SDK never run `beforeSend`**, so they
  stay clean only because nothing sensitive reaches the native scope.
- **Enabling and disabling must stay serialized**, because an off-tap during
  an in-flight async init would otherwise leave reporting on.
- **A release build with reporting off leaves no trace** of an error, since
  the error snackbar is debug-only (`app-foundation.md`).
- **A provider's or `FutureBuilder`'s failure is reported where its future
  is made, never from `build`**, which re-runs.
- **The event scrubber does not reach the feedback message**, so
  `sendFeedback` scrubs the text itself.
- **Send feedback is hidden without a DSN but works with crash reporting
  off**, so the toggle promises no crash or error reports, not no traffic.
- **Android native frames arrive R8-obfuscated**, journal entries included,
  because no mapping file is uploaded, and Dart frames would need a symbol
  upload too if builds ever pass `--obfuscate` or `--split-debug-info`.
- **With reporting on, release `debugPrint` stops printing**, because
  Sentry replaces it with a breadcrumb-only function, so attach any
  `debugPrint` hook after `SentryFlutter.init`.
