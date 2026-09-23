# Authentication

## Overview
Covers login, in-app registration, session/device management, and account
deletion — the full account lifecycle for a Zuno Chat user against a Matrix
homeserver. No repository layer: screens call `Client`/`matrix` SDK methods
directly, same as the rest of the app.

## Architecture
`SignedOutEntry` (`lib/features/auth/presentation/signed_out_entry.dart`) is
what `_AuthGate` shows when signed out. It watches `homeserverProvider`
(`lib/core/matrix/homeserver.dart`), an `AsyncNotifier<Uri>` holding the
verified server: its build runs `checkHomeserver` against `zuno.chat` in
every build mode, and `LoginPage` follows. A failure gets a retry screen
that also offers "Use another server". `use(uri)` verifies a typed server
and, on success, makes it the state; the same notifier serves both.

Before either, `SignedOutEntry` gates on the device safety check
(`lib/core/security/device_safety.dart`):

| Piece | Role |
|---|---|
| `DeviceSafety.kt` (`zuno/device_safety`, `check`) | Gathers the signals off the main thread: an attested throwaway Keystore key, one `getprop` dump, `su` paths, root manager packages (manifest `<queries>`), `Build.TAGS`. |
| `RootOfTrustParser.kt` | Minimal DER reader: `deviceLocked` and `verifiedBootState` from tag 704 of the hardware-enforced list. A software-level attestation is ignored. |
| `DeviceSafetyDecision.kt` | Pure verdict, JUnit-tested: `unlockedBootloader`, `rooted`. |
| `deviceRisksProvider` | Runs the check once per process; any failure or a 5 s timeout is an empty set. |
| `DeviceWarningPage` | Plain view of the found risks and "Continue anyway"; `deviceWarningAcknowledgedProvider` persists the tap. |

The signed-out screens themselves:

- `HomeserverPage` (`lib/features/auth/presentation/homeserver_page.dart`) —
  pushed from "Change" on sign-in or from the unreachable screen, prefilled
  with the current server and fully selected. Continue runs `use()`, shows
  the failure inline, and pops on success.
- `LoginPage` (`lib/features/auth/presentation/login_page.dart`) —
  username/password, "Sign in with your other device" under "Sign in", plus
  a conditional "Create account" button; the footer always names the server
  with "Change".
- `LinkedSignInPage` (`lib/features/auth/presentation/linked_sign_in_page.dart`)
  — scans a sign-in code with the shared `QrScannerPage` or takes the token
  typed, then signs in with `m.login.token`. A code for a server other than
  the chosen one is refused by name, never switched to.
- `RegistrationCodePage`
  (`lib/features/auth/presentation/registration_code_page.dart`) — asks for
  an email address and has the `zuno_register` Synapse module mail a
  single-use sign-up code.
  Shown only when the homeserver's registration flow requires one; carries
  a second button past it for someone who already holds a code.
- `RegisterPage` (`lib/features/auth/presentation/register_page.dart`) —
  reached from `LoginPage` or from `RegistrationCodePage`; grows a code
  field when `requiresCode` is set.
- `auth_scaffold.dart` — the shell every signed-out screen shares,
  `SignedOutEntry`'s unreachable-server screen included: an empty app bar
  (a back arrow only on a pushed screen), `AuthLogo` (mark and name), a
  soft card (`authCardKey`) with an optional title and the form, then a
  `footer` under the card for what is not the form's own action (Create
  account, the server with Change, the terms). Centered, 420 wide, one
  scroll view, so it re-centers above the keyboard. The shared mark keeps
  screen-to-screen transitions from jumping.
- `password_field.dart` — `PasswordField` plus the `PasswordReveal` mixin:
  one show/hide toggle per page, `FLAG_SECURE` while shown, back to the
  person's own setting on hide or dispose.
- `retry_wait.dart` — `RetryWait` mixin: holds a submit for as long as a
  rate limit said.

Supporting logic lives outside the widgets, in `lib/core/matrix/`:

- `registration_support.dart` — probes whether a homeserver allows in-app
  registration, and owns the UIA stage machine: `nextRegistrationStep`
  (pure: which stage to send, or "the code was refused", or "stop") and
  `runRegistration` (drives `client.register` until the flow completes,
  resumable through `RegistrationProgress`). No widget holds protocol
  logic.
- `registration_code_request.dart` — the one call to the module's
  `POST /_synapse/client/zuno/register/token`, plus its status-to-outcome
  mapping.
- `homeserver_input.dart` — parses/validates the homeserver field and
  renders a `Uri` back as typed (`homeserverInputText`), pure and
  table-tested.
- `server_name.dart` — the account's Matrix server name (not the API host):
  `ownServerName` reads `client.userID`'s domain, `serverNameProvider` falls
  back to the host of the verified `homeserverProvider` while signed out.
- `username_field.dart` — `signupUsernameChars` plus the two
  `inputFormatters` every username field shares.
- `auth_error_message.dart` — maps Matrix error codes to user-facing copy
  for login, registration, homeserver, and account-deletion failures, and
  owns `retryWaitFor` (the wait a rate limit names).

Session/device management is `ActiveSessionsPage`
(`lib/features/settings/presentation/active_sessions_page.dart`); account
deletion is `DeleteAccountTile`
(`lib/features/settings/presentation/delete_account_tile.dart`), one row
below Sign out in Settings — the app's one screen for destructive actions.
Password strength is shared infra (`lib/core/security/password_strength
.dart` + `password_strength_bar.dart`), used at registration and reused for
Settings → Security → Advanced's security phrase.

Routing: `isLoggedInProvider` + `_AuthGate` (`lib/app.dart`) is the only
top-level routing decision in the app; everything past sign-in is
`Navigator.push`.

## Data & State
- No local user/session model — the SDK's own `Client`, its logged-in state,
  and `client.userID` are the source of truth.
- `registrationSupportProvider` is an `autoDispose` `FutureProvider`
  wrapping the registration-availability probe, watched by `LoginPage`
  rather than fetched in `initState` — see Key Design Decisions. It watches
  `homeserverProvider` so a changed server is probed afresh while
  `LoginPage` stays mounted underneath.
- A registration attempt's UIA `session` lives in a `RegistrationProgress`
  held by `RegisterPage` and keyed to the exact username, password and code
  (not shared with the probe — see Key Design Decisions).
- Session/device list and verification status come straight from the SDK's
  device-list APIs; "Verify" starts emoji/SAS against another of the user's
  own sessions.
- No account/session data is cached beyond what the SDK's own local database
  already persists.

## Communication
- **Registration availability probe**: a raw `client.httpClient` POST of an
  *empty* body to `/_matrix/client/v3/register` (not `Client.register`).
  Reading the refusal tells you what the homeserver supports:
  - `401` with UIA `flows` → registration is open; the flow list decides if
    it's completable.
  - `403 M_FORBIDDEN` ("Registration has been disabled") → closed.
  - Three outcomes surface to the UI: `available` (a completable flow —
    `m.login.dummy` and `m.login.registration_token`) shows the button;
    `disabled`/`unknown` (offline, junk JSON, unexpected status) hide it;
    `unsupportedFlow` (open, but behind a stage the app can't complete —
    captcha, email/phone verification) also hides it.
  - The probe also reports `requiresRegistrationToken`, true only when
    *every* completable flow needs a code. That flag is the only thing
    deciding whether the email screen appears.
- **Real registration**: the same endpoint, called again with a real body
  and an `auth` block, once per UIA stage. The first attempt sends **no
  session** — see Key Design Decisions — so a homeserver that demands one
  refuses it and hands back a session the next attempt echoes. Against
  Synapse the full exchange is three round trips: the session-less attempt,
  `m.login.registration_token` with the session, then `m.login.dummy`.
  Without a code it stays the single dummy call it always was.
- **Sign-up code request**: `POST /_synapse/client/zuno/register/token`
  resolved against `client.homeserver` like `_matrix/…`, with
  `{"email": ...}` as `application/json` (the module refuses any other
  type with `415`), unauthenticated. `202` means proceed — **not** that an
  email was sent: the module also answers `202` when it suppressed the
  send for an address over its limit. `400`/`413` bad address, `404`/`503`
  registration closed (a module without mail config registers no route),
  `429` too many requests, `5xx` retryable.
- **Login**: standard SDK login; failures are re-mapped through
  `auth_error_message.dart` rather than shown raw, as is every sign-up
  code outcome.
- **Sign in with a code**: `client.login(LoginType.mLoginToken, token: …,
  refreshToken: true)` (`core/matrix/linked_sign_in.dart`), so the new
  session is refreshable like any other. The code is plain text,
  `ZUNO-SIGN-IN 1 <server name> <login token>`, deliberately not a URL so a
  camera app that scans it opens nothing. `M_FORBIDDEN` here means an
  invalid or expired code, not a wrong password.
- **Account deletion**: `client.deactivateAccount(auth: auth, erase: true)`,
  gated by a UIA password prompt (`client.onUiaRequest` /
  `client.uiaRequestBackground`), the same shape as `ActiveSessionsPage`'s
  own sign-out flow.
- **Homeserver validation**: shape is decided locally before any network
  call (`parseHomeserverInput`, `Uri.parse('https://$x')` rather than
  `Uri.https(x)`, so a homeserver-under-a-path parses correctly).
  Reachability failures are a separate, later question with their own
  wording (`homeserverErrorMessage`).

## Key Design Decisions
- **A sign-in code never changes the server.** The code carries the server
  name of the account that minted it; the new device compares it with the
  chosen server and refuses a mismatch, naming the server. Switching
  automatically would let a hostile code sign someone into an attacker's
  server. Typed codes always use the chosen server.
- **No App Link for sign-in codes.** A version that opened
  `https://zuno.chat/sign-in#…` from the system camera was removed: it put
  the token in camera scan history and, on any unverified build, in browser
  history. No secure messenger links devices that way; in-app scanning is
  the only path.
- **Any build can be pointed at another server; zuno.chat is the default.**
  Sign-in is the root screen and the server is a "Change" away, in release
  too. This reverses the earlier pin, which existed because a free field
  lets an impersonator say "sign in at zuno-help.chat" and collect real
  passwords through the real app; password managers key on the package,
  not the server, so they offer the zuno.chat password anywhere. Nothing
  on screen yet warns about a non-Zuno server.
- **A failed server check restores the previous homeserver.** The SDK's
  `checkHomeserver` sets `client.homeserver` to null on failure, which
  would leave the sign-in screen underneath unable to sign in; `use()`
  puts the previous value back before rethrowing.
- **Sessions use refresh tokens.** `login`/`register` pass
  `refreshToken: true` and the client sets `onSoftLogout: refreshSession`
  (`lib/core/matrix/session_refresh.dart`); the homeserver issues
  short-lived access tokens and refuses non-refreshing clients quickly.
- **Only `M_UNKNOWN_TOKEN` and `M_FORBIDDEN` end a session.** Any other
  Matrix error from `/refresh` (a rate limit, a 500) becomes a plain
  exception, because the SDK answers a `MatrixException` from the handler by
  clearing the local session — a transient server fault would otherwise wipe
  the device's keys.
- **A refused refresh is retried once against the stored token.** The app
  and the background push isolate share one refresh token, and the server
  rotates it on every use, so the loser of that race holds a dead token. The
  handler waits, re-reads the token the other isolate stored, and retries
  with it; only an unchanged token counts as a verdict.
- **The password floor is 12 characters**, matching Synapse's
  `password_config.policy.minimum_length`. A lower app floor pushes the
  refusal to the server, which answers with wording the app cannot shape.
- **Probe via raw HTTP, not `Client.register`**: the SDK method throws on
  401 and logs the caller in on success — neither behavior fits a probe
  that only wants to read the refusal shape. A raw POST is also mockable
  with `MockClient`, matching the pattern in `cloudflare_api_client.dart`.
- **The probe's session is never reused for a real registration.** Synapse
  binds a UIA session to the exact body that opened it; the probe's session
  was opened with an empty body, so any real registration replaying it is
  always refused (`M_FORBIDDEN`, not the 401-shaped
  `requireAdditionalAuthentication` the app already retries on — this
  refusal was invisible to that retry path). Fix: the first real attempt
  always opens its own session (no session on the first call).
  `isUiaSessionMismatch` recognizes the refusal by message (Synapse gives no
  distinct errcode) purely as a one-shot best-effort retry; documented as
  best-effort because its only failure mode is falling back to today's
  behavior.
- **A stage refused before a session was echoed is resent with the session
  the server just opened — whatever the stage.** Synapse will not look at a
  registration token until a UIA session exists: an `auth` block without
  `session` is answered `M_MISSING_PARAM` "Missing UIA session", with the
  stage absent from `completed` and the token never examined (its `pending`
  count does not move). That is indistinguishable, by shape alone, from a
  code the server checked and rejected — which answers `M_UNAUTHORIZED`
  "Invalid registration token" with the same empty `completed`. Only the
  session tells them apart, so the retry is what earns the right to blame
  the code. Special-casing the token stage as "a refusal is always
  authoritative" made every real signup report an invalid code while the
  token sat untouched on the server.
- **Three probe outcomes, not two** (`available` / `disabled-or-unknown` /
  `unsupportedFlow`), even though the last two look identical on screen
  (both hide the button). Kept distinct because `unsupportedFlow` is a
  genuinely different server state and is the one that matters once a
  captcha/terms stage is implemented (see Extension Guidance) — collapsing
  it now would lose that signal later.
- **No "sign up on the web" fallback line.** Zuno is the only client for its
  own homeserver; there is no web sign-up to point to. A line the reader
  can't act on doesn't belong on the screen — same rule applied to the
  Security page's cards.
- **`registrationSupportProvider` is a `FutureProvider`, not an `initState`
  fetch.** A widget test's fake-async clock never resumes a real (even
  `MockClient`-backed) HTTP future, so an `initState` fetch made the button
  untestable. A provider is overridable per test.
- **Password rules follow NIST SP 800-63B, not folk composition rules.**
  12 characters is the floor (above); 15 is what the UI steers toward; there
  are deliberately no character-class requirements — 800-63B says verifiers
  SHALL NOT require them, since that produces `Password1!` and blocks
  genuinely strong passphrases. Character variety feeds the strength *meter*
  only, never the accept/reject gate. A merely weak-but-ungated password is
  shown as weak and allowed through — refusing it would be the composition
  mistake in different clothes. The username-reuse check runs before the
  common-password check, since it's the more specific diagnosis.
- **The gate scores what is left once the guessable part is gone.** An
  exact-match list died when the floor moved to 12: almost no entry was
  that long, so `password12345` rated Strong. Common words, years, keyboard
  walks and runs are masked out; the rest is scored plus 6 bits per masked
  span, and under 20 bits is refused. That refuses one or two known-bad
  passwords with padding (`summer2026!!`) and lets three everyday words
  through as Weak. A residue-*length* rule was tried first and wrongly
  refused those passphrases. Length is counted in characters, not UTF-16
  units, because that is how the homeserver counts.
- **Two character sets, not one.** `signupUsernameChars`
  (`username_field.dart`: letters, digits, dots, underscores) is what a new
  Zuno account may be called — stricter than Matrix, because a username gets
  spoken aloud, typed on a phone and put in a URL, and a slash is the
  easiest of those to get subtly wrong. It gates every field where a local
  username is entered (sign-up, DM start, invite) live via shared
  `inputFormatters`, not just on submit. `matrixLocalpartChars`
  (`matrix_ids.dart`: adds `= - / +`) is what any localpart may *hold*, and
  is what mention detection and mention linkifying match — a federated or
  admin-created name must still resolve. `LoginPage` lowercases but does
  **not** filter: a full `@user:server` and accounts with now-disallowed
  characters must still be able to sign in, and phone keyboards
  autocapitalise.
- **A server name is not the homeserver host.** `checkHomeserver` follows
  `.well-known` and replaces `client.homeserver` with the delegated base URL
  (`zuno.chat` delegates to `https://api.zuno.chat`), so that host cannot
  stand in for the server name. User IDs and aliases come from
  `client.userID`'s domain; the signed-out screens show the domain that was
  typed or default, since no account exists yet to read one off. Only
  module URLs (calls, TURN, sign-up codes) and push still derive from
  `client.homeserver` — those endpoints live on the API host.
- **One shared message for wrong username and wrong password**
  (`M_FORBIDDEN` → "Wrong username or password") — Matrix itself won't say
  which one is wrong, to avoid account enumeration; the app preserves that
  ambiguity rather than trying to be more specific.
- **Deactivation always sets `erase: true`, no toggle.** Matches the app's
  privacy-by-default stance elsewhere. It's best-effort redaction for future
  room joiners only — not a retraction from anyone who already has the
  messages, nor across federated homeservers. That limit is real but
  deliberately not exposed as its own checkbox: surfacing a partial
  guarantee as a togglable setting reads as a stronger promise than it is.
- **Deletion is three steps**: an irreversibility warning dialog, then a
  type-your-own-Matrix-ID confirmation (deliberate extra friction beyond
  what UIA already forces, since there's no undo), then the UIA password
  prompt. The confirm button stays disabled until the typed text exactly
  matches `client.userID`.
- **Notification teardown runs after a successful `deactivateAccount`, not
  before**, unlike logout (which tears down push ahead of its own
  token-kill). The situations differ: logout's server call always
  eventually succeeds once confirmed; deactivation sits behind a password
  prompt that can still be wrong or cancelled, so tearing down push first
  would silence a still-live account for nothing. Teardown runs via
  `runBestEffort` after deactivation succeeds; a possible race between the
  pusher-delete call and the now-dead access token is accepted as harmless
  (a deactivated account can't receive pushes to lose).
- **The client is never touched outside a tap handler** in
  `DeleteAccountTile`. An earlier version subscribed to `client.onUiaRequest`
  in `initState` (copying `ActiveSessionsPage`, which can do this safely
  because it's only ever pushed once already logged in) — that crashed
  `SettingsPage`'s own tests, which render the page with no
  `matrixClientProvider` override (`matrixClientProvider` throws until
  `main.dart` overrides it). Fix: the UIA subscription opens and is
  cancelled inside `_deactivate()` itself, immediately before the request
  it's for — proving a cancelled path never touches the real client.

- **A refused code is told apart from "one more stage" by `completed`, not
  by errcode.** Both are a `401` carrying `flows` and a `session`, so
  `requireAdditionalAuthentication` cannot separate them. The stage just
  sent being absent from the response's `completed` list is what means the
  server rejected it. Synapse's errcode for this (`M_UNAUTHORIZED`) is not
  specific enough to rely on.
- **Only the token stage is read as "refused"; any other stage that fails
  to complete is resent once with the session the server just opened.**
  That retry is the pre-code behavior preserved verbatim: the old flow only
  ever sent `m.login.dummy`, and a homeserver that accepts a stage only
  once its session is echoed would otherwise have stopped registering.
  Applying the same retry to the token stage would trade a precise "that
  code is not valid" for a generic server error, so it does not.
- **Nothing tells the app the module's code alphabet or lifetime.** The
  code field filters to `A-HJ-NP-Z2-9` and the copy says "24 hours", both
  mirroring `zuno_register` (`token_ttl`). Widening the alphabet
  server-side silently truncates what people type; the module's
  `docs/design.md` (Client contract) records that the pair moves together.
- **The email screen promises nothing about delivery.** The module
  answers `202` both for a code it mailed and for one it suppressed under
  a per-address rate limit, so the copy on arrival is "Check <email> for
  your code", true in both cases. A "code sent" confirmation would be a
  lie roughly one time in the cases that matter.
- **The sign-up code field sits outside `AutofillGroup` with
  `autofillHints: null`**, so a password manager cannot capture a one-time
  code. "No hints" is not enough — see the next decision.
- **Every text field in the app states its autofill choice.** Flutter leaves
  autofill *on* for a `TextField` unless `autofillHints` is `null`; an empty
  list still opens a session with the password manager on focus and hands it
  the field's text — message drafts included. Credential fields name real
  hints, everything else passes `null`, and
  `test/core/security/autofill_opt_in_test.dart` fails on a field that says
  nothing.
- **Re-auth prompts never offer a save; change password offers one only
  after the server accepts.** `askPasswordForUia`, the session-token tile
  and recovery-code entry sit in an `AutofillGroup` that cancels on dispose.
  `ChangePasswordDialog` performs the change itself and calls
  `finishAutofillContext()` on success, so a refused change is never
  offered for saving; its read-only username field lets a manager update
  the right entry.
- **The security phrase fields opt out of autofill.** A manager would offer
  the saved account password there, and the homeserver sees that password
  at login — reusing it would hand the server the key backup.
- **"Confirm password" stays, beside the reveal toggle.** There is no email
  reset, so a typo at sign-up loses the account.
- **A rate limit holds the submit for as long as the server said.**
  `retryWaitFor` reads `retry_after_ms`, then the `Retry-After` header the
  spec now prefers, capped at 5 minutes. The hold lives in the submit
  handler, not only the button — the keyboard's Done calls it directly.
- **An interrupted sign-up resumes its session.** A dropped connection
  after the code stage leaves the code pending in a session the app used to
  discard, so the next tap read as "code not valid". `RegistrationProgress`
  keeps the session; it is reused only while username, password and code
  are unchanged (Synapse binds the session to the first body, first
  password included), restarted once if the server forgot or replaced it,
  and a taken username after a network failure tries signing in with the
  same credentials. Best-effort: built from Synapse's documented behaviour,
  not verified against a live one.
- **The probe is dropped with `LoginPage` and retried when inconclusive.**
  The provider throws on `unknown` so Riverpod's backoff re-asks; cached for
  the app's lifetime, one transient failure hid "Create account" until
  restart, and a debug build kept the first server's answer.
- **Usernames are stricter than Synapse on purpose**: no leading underscore
  (bridges), at least one letter (Synapse refuses all-digit names; "needs a
  letter" is the rule a person can follow), and short enough for a 255-byte
  user ID. Each would otherwise come back as the generic "not allowed".
- **"Change" pushes the server screen rather than popping to it.**
  `LoginPage` is always the root; the server screen is a modal step that
  pops back, so nothing is rebuilt and the probe re-runs in place.
- **An email address is not an account identifier here.** It buys a code
  and nothing else: no account is tied to it, and there is still no email
  to reset a lost password. `docs/brand-voice.md` carries the claim in the
  form the app is allowed to make it.
- **The unsafe-device warning informs, it never blocks.** It shows on the
  signed-out screen until "Continue anyway" is tapped once, then never
  again. A failed or slow check shows nothing: a false "unsafe" on a first
  launch costs more than a miss, and someone hiding root deliberately
  already knows.
- **Unlocked means orange or red, never yellow.** A relocked custom system
  (attested `SelfSigned`) is safe. Attestation and boot properties are
  OR-ed, so a spoofed attestation with honest properties still warns, and
  a device without attestation falls back to properties. The certificate
  chain is not verified: whoever could forge it locally could hook the app
  anyway. Play Integrity is out: it needs Google and a server, and fails
  relocked custom systems.
- **The check is lazy, watched only by `SignedOutEntry` and only until
  acknowledged.** `main()` cannot know whether a session exists before the
  client is up, so running it there would generate an attestation key on
  every signed-in cold start. `ZunoSplash` holds while it runs, continuous
  with the boot splash.
- **Creating an account accepts the terms, and the screen says so.**
  `RegisterPage` ends with one line and links to the terms and the privacy
  policy (`zuno_links.dart`). Google Play requires acceptance before anyone
  can post. No checkbox, and the line appears only on `zuno.chat`: another
  server's terms are not Zuno's. The About page still links the policy.

## Gotchas & Constraints
- `homeserverProvider` is kept alive, but `client.clear()` (sign-out) nulls
  `client.homeserver`. Signing out and back in within one process therefore
  reaches `client.login` with no homeserver and fails with "No homeserver
  specified"; re-verifying on each signed-out entry (autoDispose) is the
  intended fix.
- Any test that renders a signed-out screen must override
  `homeserverProvider` (`FixedHomeserver` in `test/helpers/`), or its
  build calls `checkHomeserver` over the real network.
- A test that pumps `SignedOutEntry` or a signed-out `ZunoApp` must override
  `deviceRisksProvider` (`overrideWithValue(const AsyncValue.data({}))`),
  or the first frames are the splash instead of the sign-in screen.
- `test-keys` and `ro.debuggable=1` count as `rooted`. Some cheap stock
  systems ship `test-keys`; the warning is warranted (anyone can sign a
  system update for them), the label is approximate.
- A homeserver's UIA `flows` may list a captcha or terms stage as
  *optional* alongside `m.login.dummy`; `registration_support.dart` treats
  any one completable flow as sufficient and routes around the harder
  stage. A mandatory captcha/terms requirement is the only configuration
  that actually deters abuse, and it's exactly the one the app currently
  can't complete (classifies as `unsupportedFlow`, hides the button
  entirely) — see Extension Guidance before enabling either server-side.
- `Uri.https(x)` rejects any input containing a slash and mis-parses a
  pasted Matrix ID (`@user:example.org` reads "example.org" as a port).
  Homeserver parsing must go through `parseHomeserverInput`
  (`Uri.parse('https://$x')`), not construct a `Uri` directly.
- A malformed-but-syntactically-legal homeserver input (e.g. spaces) is
  *accepted* by naive `Uri` construction via percent-encoding, then fails
  much later as an opaque `SocketException: Failed host lookup`. Validation
  must happen before the network call, not be inferred from its failure.
- Login and homeserver-screen network failures need different wording even
  for the same underlying exception: on the homeserver screen the likely
  cause is the address; on login it's connectivity. Don't share one generic
  "network error" string across both screens.
- No refusal string shown on the homeserver/login/register screens may be
  multi-line or contain a caret diagram — these screens render every line
  they're given verbatim, so a raw `FormatException`/`Uri` error leaks
  straight to the user if not passed through `auth_error_message.dart`.
- Deactivation and logout intentionally clear local state through different
  final steps (deactivation skips `logout()`'s own doomed server round trip
  against an already-dead token) but both end by calling
  `client.clear(reason: SessionClearReason.logout)` and flipping
  `isLoggedInProvider`. Keep both paths ending there if either changes.
- On Android, `enableSuggestions: false` ORs the visible-password variation
  into the input type. On an email or URL field that replaces the `@` or
  `/` keyboard, so those fields set only `autocorrect: false`.
  `PasswordField` sets no `keyboardType` for the same reason: hidden, it
  must reach the keyboard exactly as a plain obscured field does.
- Flutter hands an autofill service only a field's hints, hint text and
  value — no input type, no label. A field without hints cannot be
  recognised, which is why re-auth prompts name `AutofillHints.password`.
- Nothing on the submit side can force a save offer. When a service answers
  the first focus with no response, Android ends the session at once,
  ignores every later value, and `finishAutofillContext()` commits nothing.
  Seen with Google's service declining even the login form; `cmd autofill
  set log_level verbose` shows it. An explicit save needs Credential
  Manager, not built.
- The reveal icon is wrapped in `ExcludeFocus`; otherwise "next" from the
  password lands on it instead of the confirmation.
- No field autofocuses, and every submit or push calls `closeKeyboard()`
  (`lib/core/ui/keyboard.dart`) first. A popped route hands focus back to
  the field that had it, so without the unfocus before the push the
  keyboard comes back on return from Change or Create account.
- No recovery-key prompt after registration, unlike after login — a
  brand-new account has no Secure Backup to restore yet. Don't add one
  without also handling "nothing to restore".

## Extension Guidance
- **Adding a UIA stage the app can complete (captcha, terms of service)**:
  extend `supportedRegistrationStages` in `registration_support.dart`, give
  `nextRegistrationStep` the input the stage needs, and add its UI to
  `RegisterPage` — do this *before* turning on the matching server-side
  requirement in Synapse. Landing the client stage and the server config
  separately breaks signup in whichever order they land; the same ordering
  applies to `registration_requires_token` itself, since a server that
  demands a code the app cannot send hides "Create account" entirely.
- **Changing how the loop decides**: `nextRegistrationStep` is pure and
  table-tested, and `runRegistration` is driven by a `Client` — both are
  testable without a widget. Protocol changes belong there, never in
  `RegisterPage`.
- **New auth-adjacent error copy** belongs in `auth_error_message.dart`
  next to `loginErrorMessage`/`registrationErrorMessage`/
  `deactivateAccountErrorMessage`/`homeserverErrorMessage` — don't grow a
  second ad hoc error-formatting function elsewhere; `RegisterPage`'s old
  private `_friendlyError` was folded in for this reason.
- **New password-gated flows** (e.g. a future re-auth prompt) should reuse
  `password_strength.dart`'s rules rather than inventing new composition
  requirements — the NIST rationale applies anywhere Zuno asks someone to
  pick a secret.
- **Session/device UI changes** belong in `ActiveSessionsPage`; it's the
  one existing example of a safely-initState-subscribed UIA flow (safe
  specifically because it's only pushed once already logged in — don't copy
  that pattern into a widget that can render pre-login or without a real
  client, per the `DeleteAccountTile` gotcha above).
- **Data export ("download my data")** is a known gap, not yet built —
  natural extension point is alongside `DeleteAccountTile` in Settings.

## Dependencies / Integration
- **Matrix SDK** (`Client`) for login, registration, session/device list,
  verification, and `deactivateAccount` — no repository layer in between.
- **Security & verification** (`lib/core/security/`) — shares
  `password_strength.dart` with registration; session verification
  (emoji/SAS) is reached from the same device list this feature renders.
- **Notification delivery** (`NotificationDeliveryProvider`) — torn down
  after account deletion succeeds; see the ordering decision above.
- **Settings** — hosts `DeleteAccountTile` and links to
  `ActiveSessionsPage`; both are Settings-page features, not separate
  navigation destinations.
