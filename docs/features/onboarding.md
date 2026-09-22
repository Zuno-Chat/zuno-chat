# First-Run Onboarding

## Overview

Decides what, if anything, to ask someone the first time they reach the
room list on this device, then walks them through it one page at a time.
Not a fixed wizard: most launches show nothing at all.

## Architecture

- `lib/core/onboarding/onboarding_step.dart` — the pure decision core.
  `OnboardingStep` enum (`welcome`, `profile`, `notifications`,
  `deliveryMethod`, `batteryExemption`, `approveDevice`, `setUpRecovery`),
  `onboardingSteps(...)` (account facts → ordered list) and
  `stepsAfterDeliveryChoice(...)` (adjusts a running flow once a delivery
  method is picked). No `Client`, no platform channel, no
  `SharedPreferences`.
- `lib/core/onboarding/onboarding_provider.dart` — the wiring. Gathers the
  facts (`OnboardingStore.justRegistered`, askable notification permission,
  `needsBatteryExemptionFor(mode)`, `AccountSecurityFacts`, joined rooms,
  recovery-prompt cooldown, already-shown steps) into
  `onboardingStepsProvider` (`FutureProvider`, recomputed on every sync
  tick) and holds `OnboardingStore` (persistence + in-flight guard).
- `lib/features/onboarding/presentation/onboarding_flow_page.dart` — a
  `PageView` with `NeverScrollableScrollPhysics`: pages only advance when a
  step completes or Skip is tapped. Skip sits at the top right. Every page
  is the same `_StepScaffold`, a thin wrapper over the shared `StepLayout`
  (`app-foundation.md`): an icon or art in a soft circle, centered title
  and one paragraph, one primary verb button pinned at the bottom. On the
  name step the circle and its camera badge are the photo picker. The dots
  sit in a fixed 32 px slot under the pages, empty for a single step, so
  the button is at the same height on every step and in every flow. They
  are under the button, not above it, because the button lives inside the
  sliding page and the dots must not slide.
- Trigger: `room_list_page.dart` listens to `onboardingStepsProvider` and
  pushes the flow over `RoomListPage` when it resolves non-empty.
  `_AuthGate` keeps its single routing decision; onboarding is not a route.
- `register_page.dart` calls `OnboardingStore.markRegistered` after
  `client.register` succeeds; that flag is what makes `welcome` and
  `profile` registration-only.

## Steps and their conditions

| Step | Fires when | Completes by |
|---|---|---|
| `welcome` | just registered | "Get started" |
| `profile` | just registered | "Save" (enabled once a name or photo is set) |
| `notifications` | permission not granted and not permanently denied | OS answers; if full-screen call alerts are still off, one "Open settings" page, advancing on return |
| `deliveryMethod` | not yet answered on this device (login or registration) | "Continue" after picking a method |
| `batteryExemption` | chosen mode depends on it and Android hasn't exempted the app | OS grants it (checked on resume) |
| `approveDevice` | recovery exists, this device lacks identity keys | returning from `ApproveThisDevicePage` |
| `setUpRecovery` | no recovery, has conversations, prompt not on cooldown | returning from `SecureBackupPage` |

`batteryExemption` is held back while `deliveryMethod` is pending; the
flow inserts it right after the choice (or drops a pending one for FCM)
via `stepsAfterDeliveryChoice`. Once `deliveryMethod` was answered, the
predicate adds it from the stored mode as before.

## Data & State

- **Step list**: computed, never stored. The flow page copies it into
  mutable state so the delivery choice can add or remove the battery step.
- **`OnboardingStore`** (`SharedPreferences`, per account):
  `onboarding.shown.<userId>` — steps already asked, with an in-memory
  mirror to close the race with a slow provider recomputation;
  `onboarding.registered.<userId>` — set by the register page, never
  cleared (the shown-set stops the steps from repeating);
  `flowInProgress` (session-only) — stops a mid-flow recomputation from
  opening a second flow. Unknown stored step names are dropped, not fatal.
- **Marking shown happens on exit, not entry** — when a step finishes or
  is skipped. An abandoned flow resumes at the step it stopped on.
- The delivery step writes `notificationDeliveryModeProvider` and calls
  `kickOffDeliveryMode` (`notification_delivery_provider.dart`), the same
  follow-up Settings uses.

## Key Design Decisions

- **A predicate-driven queue, not a wizard.** Each step carries its own
  condition; the common case is an empty list. Asking everything cold is
  how notification permission gets reflexively denied and recovery codes
  get generated and lost at minute zero.
- **Registration is a stored flag, not "no display name".** Synapse fills
  the display name with the username at registration, so a name-based
  gate never fired for new accounts. Login never sets the flag.
- **No information-only pages.** A step that turns into "done, continue"
  after its action advances by itself instead. The welcome page is the one
  deliberate exception, and it is registration-only.
- **No swiping.** Steps have side effects (OS dialogs, settings screens),
  so the pager only moves on completion or Skip; forward and back swipes
  are disabled rather than treated as skips.
- **The recovery dialog defers to the flow.** `_maybeOfferRecovery`
  (`room_list_page.dart`) awaits `onboardingStepsProvider` and stands down
  while the flow is open or has pending steps
  (`recoveryPromptDefersToOnboarding`, `security_prompt.dart`). Both share
  the 7-day cooldown, so whichever asks first silences the other; without
  this the dialog won the post-login race and the slider never showed its
  recovery step.
- **Reads raw `AccountSecurityFacts`, not the collapsed status.** The
  card's precedence ranks `deviceWaiting` above `deviceLocked`, which
  masked "this device can't read your history" on a real second-device
  login.
- **Every step is skippable.** An unskippable step is a toll gate people
  answer at random.
- **The name field never autofocuses; Save, Skip and every done action
  call `closeKeyboard()` first.** Save closes it before the profile
  request, not after, so the spinner never sits under a keyboard.
- **`setUpRecovery` never fires on a brand-new account** (`hasConversations`
  gate) and honours the recovery prompt's cooldown.

## Gotchas & Constraints

- Every fact read fails toward "don't ask": a missing permission channel
  reads as "can't ask", a failed battery check as "doesn't need it".
- `_NotificationsStepState` fetches the pre-request permission status in
  `initState`, never immediately before `.request()` — a permission_handler
  quirk otherwise makes the OS dialog's first tap not register on the
  very first ask.
- `onboardingStepsProvider` resolves empty first on a fresh sign-in (the
  device-approval fact needs a sync); the room list's `ref.listen` opens
  the flow when the later answer arrives.
- `PageView` only builds the current page, so a step's `initState` runs
  when it becomes current, and lifecycle-resume checks only fire for the
  page on screen.

## Extension Guidance

1. Add the enum variant and its predicate to `onboardingSteps()`, keeping
   it pure; thread any new fact through `onboardingStepsProvider` with the
   fail-safe default.
2. Add its page to `_StepPage` in `onboarding_flow_page.dart` using
   `_StepScaffold` with one primary verb button; advance from the action's
   completion, never from a "Continue" on a result screen.
3. Unit-test the predicate against `onboardingSteps()`; widget-test the
   page in `onboarding_flow_page_test.dart` (every step is covered by the
   one-page-one-button loop there).

## Dependencies / Integration

- **Auth**: triggered after landing on `RoomListPage`; registration sets
  the store flag.
- **Security / recovery**: shares `AccountSecurityFacts`, the recovery
  prompt's cooldown and `hasConversations` gate, and hands off to
  `ApproveThisDevicePage` / `SecureBackupPage`.
- **Notifications**: reads `permission_handler` status and the delivery
  mode; the delivery step is the onboarding face of the Settings picker.
