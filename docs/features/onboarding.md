# Onboarding

Decides what, if anything, to ask someone the first time they reach the room
list on this device, then walks them through it one page at a time. It is a
queue of first-run asks computed from account facts, not a fixed wizard, and
most launches show nothing at all. Each step's own behavior lives with its
feature; this doc covers which steps exist, when they show and how the flow
moves between them.

## Architecture

| Piece | Role |
|---|---|
| `onboarding_step.dart` | The pure decision core. The `OnboardingStep` enum is in flow order, `onboardingSteps(facts)` returns the pending list, and two helpers adjust a running flow. |
| `onboardingStepsProvider` | Waits for the first sync, gathers the facts (permissions, delivery mode, account security, joined chats, steps already shown) and recomputes as they change. |
| `OnboardingStore` | Per account, in `SharedPreferences`: the steps already shown and whether the account registered on this device. |
| `OnboardingFlowPage` | A `PageView` that cannot be swiped. Each page is an illustration, a title, one paragraph and one primary button on the shared `StepLayout` (`app-foundation.md`). |
| `room_list_page.dart` | The trigger: pushes the flow over whatever is on top once the provider settles on a non-empty list, so `_AuthGate` keeps its single routing decision. |

The step list is computed, never stored; the flow page copies it into its
own state so answers can add or remove steps while it runs. A step is marked
shown when it finishes or is skipped, so an abandoned flow resumes where it
stopped and every step shows at most once per account on this device.
`RegisterPage` sets the registered flag inside the sign-in hold
(`authentication.md`), so the first step list already sees it.

## Steps

| Step | Shows when | Moves on when | Behavior in |
|---|---|---|---|
| `welcome` | Just registered on this device | "Get started" | this flow |
| `profile` | Just registered on this device | Save | this flow |
| `notifications` | Permission not granted and not permanently denied | The OS answers; on Android, a follow-up page may ask for full-screen call alerts | `notifications.md`, `calls.md` |
| `deliveryMethod` | More than one delivery mode is offered | Continue | `notifications.md` |
| `batteryExemption` | The chosen mode needs a battery exemption the app lacks | The OS grants it | `notifications.md` |
| `autostart` | The maker has an autostart screen (Xiaomi, Oppo, Vivo, Huawei) | "Open settings"; Android cannot report the setting, so it is asked once | `notifications.md` |
| `approveDevice` | Recovery exists and this device lacks identity keys | The approval page is gone | `security-verification.md` |
| `setUpRecovery` | No recovery, at least one joined chat, prompt not on cooldown | The recovery page is gone | `security-verification.md` |
| `confirmPeople` | Not yet shown on this device; always last | Continue | `security-verification.md` |

The flow adjusts itself in two places:

- **The delivery choice places the battery step**, inserting it right after
  the choice or dropping it, depending on the mode picked.
- **Notifications gate the three delivery steps.** If the `notifications`
  step ends without a grant, the delivery, battery and autostart steps are
  dropped and marked shown.

## Decisions

- **A predicate-driven queue, not a wizard.** Asking everything cold is how
  the notification permission gets reflexively denied and recovery codes get
  generated and lost at minute zero.
- **One flow per sign-in, on synced facts.** Device approval and chats are
  known only after a sync, and deciding earlier would split onboarding in
  two, so the provider awaits `firstSyncProvider` as well as the sign-in
  hold.
- **Registration is a stored flag, not "no display name"**, because Synapse
  sets the display name to the username at registration.
- **Declining notifications answers the delivery steps too.** They are
  marked shown, not merely hidden, or turning notifications on later in
  Settings would open the flow over Settings.
- **No information-only pages.** A step whose action is done advances by
  itself, except `welcome` and `confirmPeople`, because nobody looks for a
  protection they do not know exists.
- **Skip only where there is something to decline**, because an
  unskippable ask is a toll gate people answer at random.
- **No swiping and no system back**, because steps have side effects such
  as OS dialogs and settings screens.
- **The recovery dialog defers to the flow.** The room list's recovery
  dialog stands down while the flow is open or pending, and both share one
  cooldown, or the dialog would win the race after sign-in.
- **The provider reads raw `AccountSecurityFacts`, not the collapsed
  status**, because onboarding asks only about recovery and this device's
  keys.

## Gotchas

- Every fact fails toward "do not ask", including a slow or failed check.
- The notifications step reads the permission status in `initState`, or a
  `permission_handler` quirk drops the OS dialog's first tap.
- `_advance(from)` acts only while `from` is current, so a late save or a
  double tap cannot move the next step on too.
- Security steps advance only once their page is fully gone, because
  `popForward` under a leaving page falls back to the reverse exit.
- `PageView` builds only the current page, so a step's `initState` and
  resume checks run only while it is on screen.
- The delivery step saves through the Settings picker's path and continues
  with the mode actually saved.
- A new step's predicate stays pure and goes before `confirmPeople`.
