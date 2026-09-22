# Crash Reporting

## Overview
Unhandled errors go to Sentry, but only when all three hold: the user
switched it on (Settings → About, off by default), the build is
release, and a DSN was compiled in. Any one missing and Sentry is never
initialized — the app behaves exactly as it did before this existed.

Feedback (Settings → Send feedback) uses the same DSN and scrubber but
not that gate: tapping Send is the consent, so it works with crash
reporting off. It needs only a compiled-in DSN.

## Architecture
| File | Owns |
|---|---|
| `core/errors/crash_reporting.dart` | Gate, Sentry options, install ID, enable/disable |
| `core/errors/crash_scrubber.dart` | Pure redaction of Matrix identifiers and tokens |
| `core/errors/global_error_handler.dart` | The pre-existing error funnel |
| `core/errors/feedback.dart` | `sendFeedback`, the `feedbackAvailable` gate |
| `features/feedback/presentation/feedback_sheet.dart` | The one-field sheet and its snackbar |

`shouldReportCrashes` is a pure predicate over the three conditions, so
the release-only path stays testable from a debug test run.

Sentry's own integrations do the capturing on `FlutterError.onError` and
`PlatformDispatcher.onError`; `reportUnhandledError` stays capture-free
so those errors are not reported twice. Only the outer `runZonedGuarded`
in `main()` captures explicitly, via `reportZoneError` → `captureCrash`,
because Sentry hooks that zone only when it owns `appRunner`, which it
does not here. `installGlobalErrorHandlers` chains whatever handler it
replaces, so either init order works.

Three isolates initialize separately: the app, the UnifiedPush headless
entry, and the FCM background handler. The two headless ones go through
`initHeadlessCrashReporting()`, which turns session tracking off — a
push wake is not a user session, and counting it as one would bury the
crash-free rate under hundreds of one-second sessions a day.

`sendFeedback` builds its own `SentryClient` over a bare `SentryOptions`,
sends one feedback event and closes it. It never touches the global hub,
so it starts no native SDK and installs no error hooks, and it takes the
same path whether crash reporting is on or off. The message goes through
`scrubText` first; the event carries the release and an `os` tag, and no
user — not even the install ID. An empty `SentryId` (what `HttpTransport`
returns on any network or HTTP failure) becomes `FeedbackNotSent`.

## Data & State
| Key | Holds |
|---|---|
| `settings.crash_reporting` | The opt-in, default false |
| `crash_reporting.install_id` | Random 16-byte hex, minted on first opt-in |

The install ID is the only identity attached: no Matrix ID, no
homeserver, no IP (`sendDefaultPii` stays false). It is minted when
reporting is first switched on, not at install, so opting out leaves
nothing behind.

`beforeSend` and `beforeBreadcrumb` run everything through `scrubText`,
which redacts `@user:host`, `!room:host`, `#alias:host`, event IDs of
both forms, `access_token=`-style parameters and bearer tokens.
Screenshots, view hierarchy, session replay, user-interaction
breadcrumbs and all tracing stay off.

## Key Design Decisions
- **Opt-in, default off** — an E2EE client must not phone home before
  being asked. The cost is accepted: most crashes are never seen.
- **Release-only** — dev crashes would swamp the project, and the
  console dump already covers development.
- **Sentry's integrations capture, the existing funnel does not** —
  hooking both would double-report every Flutter error.
- **An anonymous install ID, not the Matrix ID** — enough to tell one
  user hitting a crash 40 times from 40 users hitting it once, without
  handing an identifier to a third party.
- **Feedback bypasses the opt-in, crashes do not** — a crash report is
  sent on the user's behalf, feedback is sent by the user. Gating it on
  the crash toggle would hide it from almost everyone.
- **Feedback is anonymous, so there is no reply** — a contact field would
  hand an identifier to a third party. The sheet says so.
- **The DSN comes from `--dart-define-from-file=.env`** — a
  gitignored file, with `.env.example` committed. A missing DSN
  disables reporting rather than failing the build.

## Gotchas & Constraints
- **Native crashes never run `beforeSend`.** The Android SDK builds and
  sends those itself, so Dart-side scrubbing does not apply to them.
  What protects them is that nothing sensitive reaches the native scope:
  Dart breadcrumbs are scrubbed by `beforeBreadcrumb` before scope sync,
  and the user is set on the scope as well as in `beforeSend`.
- **Enabling and disabling must stay serialized.** `SentryFlutter.init`
  is async; a fast off-tap during an in-flight init finds
  `Sentry.isEnabled` still false, no-ops, and leaves reporting on once
  the init lands. `setCrashReportingEnabled` chains every change onto
  one future for exactly this reason.
- **The unhandled-error snackbar is debug-only**
  (`showUnhandledErrorSnackBars`, a mutable top-level rather than a bare
  `kDebugMode` check so the release path is testable). In release with
  reporting off, an unhandled error leaves no trace at all.
- **`scrubEvent` does not reach `contexts.feedback.message`**, which is
  why `sendFeedback` scrubs the text itself before building the event.
- **The Send feedback tile is hidden without a DSN**, so an ordinary
  debug build never shows it. `flutter run
  --dart-define-from-file=.env` exercises the real send in debug.
- **The `os` tag is `Platform.operatingSystemVersion`**, expected on
  Android to be the firmware build ID (`BP4A…`) rather than "Android 16"
  — not yet confirmed on a device. A readable version needs
  `device_info_plus`.
- **The crash toggle promises "No crash report is sent while this is
  off"**, not "nothing" — feedback does send while it is off.
- **Obfuscated release stack traces arrive unreadable** until debug
  symbols are uploaded (`sentry_dart_plugin`, not wired up).
