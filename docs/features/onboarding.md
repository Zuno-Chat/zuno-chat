# Onboarding

Decides what, if anything, to ask someone the first time they reach the room
list on this device, then walks them through it one page at a time. It is a
queue of first-run asks computed from account facts, not a fixed wizard, and
most launches show nothing at all. Each step's own behavior lives with its
feature; this doc covers which steps exist, when they show and how the flow
moves between them.

## Architecture

- `lib/core/onboarding/onboarding_step.dart`: the pure decision core, with no
  `Client`, platform channel or `SharedPreferences`. The `OnboardingStep`
  enum is in flow order. `onboardingSteps(facts)` returns the pending list,
  `stepsAfterDeliveryChoice` and `stepsAfterNotificationsAnswer` adjust a
  running flow, and `offersSkip` says which steps can be skipped.
- `lib/core/onboarding/onboarding_provider.dart`: the wiring.
  `onboardingStepsProvider` waits for `firstSyncProvider`, gathers the facts
  and recomputes as they change. The facts are the registered flag, the
  notification permission, whether the delivery mode needs a battery
  exemption, whether the maker has an autostart screen,
  `AccountSecurityFacts`, joined chats (spaces do not count), the recovery
  prompt's cooldown and the steps already shown. It also holds
  `OnboardingStore`.
- `lib/features/onboarding/presentation/onboarding_flow_page.dart`: a
  `PageView` that cannot be swiped, so a page moves only when its step
  completes or Skip is tapped. Every page is a `_StepScaffold` over the
  shared `StepLayout` (`app-foundation.md`): an illustration, a title, one
  paragraph and one primary verb button. Skip and the progress dots stay put
  while the pages slide.
- **Trigger**: `room_list_page.dart` listens to `onboardingStepsProvider`
  and, on a settled, non-empty answer with a signed-in user, pushes the flow
  in a `ForwardExitPageRoute` over whatever is on top. A reloading answer
  still carries the previous list, so only a settled one counts.
  `_AuthGate` keeps its single routing decision.
- **Registration**: `RegisterPage` calls `markRegistered` inside the
  sign-in hold (`authentication.md`), so the first step list already sees
  it. That flag is what makes `welcome` and `profile` registration-only.

### State

The step list is computed, never stored. The flow page copies it into its
own state, so the notifications and delivery answers can remove or insert
steps while the flow runs.

`OnboardingStore` keeps the rest in `SharedPreferences`, per account. It is
rebuilt per session (it watches `isLoggedInProvider`), because the iOS
sign-out wipe keeps the process (`app-foundation.md`).

| Entry | Holds |
|---|---|
| `onboarding.shown.<userId>` | Steps already asked. An in-memory mirror closes the race with a slow provider recomputation; unknown stored names are dropped, not fatal. |
| `onboarding.registered.<userId>` | Set by `RegisterPage` and never cleared; the shown set is what stops the steps from repeating |
| `flowInProgress` (memory only) | Stops a recomputation mid-flow from opening a second flow |

A step is marked shown on exit, not on entry: when it finishes or is
skipped. An abandoned flow therefore resumes at the step it stopped on, and
every step shows at most once per account on this device.

## Steps

| Step | Shows when | Moves on when | Behavior in |
|---|---|---|---|
| `welcome` | Just registered on this device | "Get started" | `onboarding_flow_page.dart` |
| `profile` | Just registered on this device | Save | `onboarding_flow_page.dart` |
| `notifications` | Permission not granted and not permanently denied | The OS answers. On Android, if full-screen call alerts are still off, one follow-up page opens their settings and advances on return. | `notifications.md`; the follow-up page in `calls.md` |
| `deliveryMethod` | The platform offers more than one delivery mode, and notifications are allowed or asked in this flow | Continue; the stored mode is preselected, so Continue alone keeps it | `notifications.md` |
| `batteryExemption` | The platform has battery exemptions, the chosen mode depends on one, and the app is not exempt; same notifications condition | The OS grants it, checked on resume | `notifications.md` |
| `autostart` | The maker's autostart screen exists on this device (Xiaomi, Oppo, Vivo and Huawei families); same notifications condition | "Open settings", then it advances. Android cannot report the setting, so it is asked once. | `notifications.md` |
| `approveDevice` | Recovery exists and this device lacks identity keys | `ApproveThisDevicePage` has closed and is fully gone | `security-verification.md` |
| `setUpRecovery` | No recovery, at least one joined chat, and the recovery prompt is not on cooldown. A new account gets it once it joins its first chat. | `SecureBackupPage` has closed and is fully gone | `security-verification.md` |
| `confirmPeople` | Not yet shown on this device, so every account sees it once, existing ones on their next launch; always last | Continue | `security-verification.md` |

The flow adjusts itself in two places:

- **The delivery choice places the battery step.** While `deliveryMethod`
  is pending, `batteryExemption` is held back; once a mode is picked,
  `stepsAfterDeliveryChoice` inserts it right after the choice or drops it.
  Once `deliveryMethod` has been answered, the predicate adds the battery
  step from the stored mode.
- **Notifications gate the three delivery steps.** When the
  `notifications` step ends without a grant (declined or skipped),
  `stepsAfterNotificationsAnswer` drops `deliveryMethod`, `batteryExemption`
  and `autostart`, and they are marked shown.

## Decisions

- **A predicate-driven queue, not a wizard.** Each step carries its own
  condition, and the common case is an empty list. Asking everything cold
  is how the notification permission gets reflexively denied and recovery
  codes get generated and lost at minute zero.
- **One flow per sign-in, on synced facts.** Device approval and chats are
  known only after a sync, and deciding earlier would split onboarding in
  two. The sign-in hold (`authentication.md`) covers most of it, but
  `client.login` can give up waiting for the sync, so the provider also
  awaits `firstSyncProvider`. It does so before reading the user, so the
  dependency outlives a build made while signed out.
- **Registration is a stored flag, not "no display name".** Synapse sets the
  display name to the username at registration, so a name-based check never
  fires for a new account. Signing in never sets the flag.
- **Declining notifications answers the delivery steps too.** They are
  marked shown, not merely hidden; otherwise turning notifications on later
  in Settings would open the flow over Settings on the next sync. The
  Delivery page in Settings is where they are set afterward.
- **No information-only pages.** A step whose action is done advances by
  itself instead of turning into "done, continue". There are two
  deliberate exceptions: `welcome` (registration only) and `confirmPeople`,
  which every account sees once, because nobody looks for a protection
  they do not know exists (`security-verification.md`).
- **Skip only where there is something to decline** (`offersSkip`). An
  unskippable ask is a toll gate people answer at random. `welcome`,
  `deliveryMethod` (its stored mode is preselected) and `confirmPeople` have
  nothing to decline, so their own button moves on.
- **No swiping and no system back.** Steps have side effects (OS dialogs,
  settings screens), so the pager moves only on completion or Skip; swipes
  are disabled rather than treated as skips.
- **Finishing moves forward** (`ForwardExitPageRoute.popForward`,
  `app-foundation.md`): the flow leaves like one more pager step, not the
  way it came in.
- **The recovery dialog defers to the flow.** `_maybeOfferRecovery` in
  `room_list_page.dart` waits for `onboardingStepsProvider` and stands down
  while the flow is open or has pending steps
  (`recoveryPromptDefersToOnboarding`). Both share one cooldown, and
  leaving the `setUpRecovery` step stamps it, so whichever asks first
  silences the other. Without this, the dialog would win the race after
  sign-in and the flow would never show its recovery step.
- **The provider reads raw `AccountSecurityFacts`, not the collapsed
  status.** Onboarding asks only about recovery and this device's keys, and
  the recovery step has conditions of its own (a joined chat, no
  cooldown).

## Gotchas

- Every fact fails toward "do not ask". A missing permission channel means
  "cannot ask"; a failed battery check means "not needed", as does a slow
  one inside the flow.
- The notifications step reads the permission status in `initState`, never
  just before `.request()`. Otherwise a `permission_handler` quirk drops
  the OS dialog's first tap on the very first ask.
- `_advance(from)` acts only while `from` is the current step. Otherwise a
  save landing after Skip, or a double tap on Continue, would move the next
  step on as well.
- Security steps advance only once their page is fully gone
  (`route.completed`): `popForward` under a page that is still leaving falls
  back to the normal reverse exit.
- `PageView` builds only the current page, so a step's `initState` runs when
  it becomes current, and its resume checks fire only while it is on
  screen.
- The delivery step is the onboarding face of the Settings picker. It saves
  through the same path (`kickOffDeliveryMode`) and continues with the mode
  actually saved, never with an unsaved pick.

## Adding a step

A new step's predicate goes in `onboardingSteps()`, kept pure and before
`confirmPeople`, and any new fact reaches it through
`onboardingStepsProvider` with a default that fails toward not asking. Its
page joins `_StepPage` on `_StepScaffold`, under the Skip and auto-advance
rules above. `onboarding_flow_page_test.dart` loops over every
`OnboardingStep` to check the shared layout, so a new page is held to it at
once; its own behavior gets its own test there.

## Testing

- A test that reads the real `onboardingStepsProvider` overrides
  `firstSyncProvider`, since `buildTestClient` never syncs
  (`app-foundation.md`).
