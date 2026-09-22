# Security & Verification

## Overview

Covers E2EE, cross-signing, device verification (QR/emoji), recovery code
(secure backup / SSSS / key backup), and the account-security status UX
that ties them together. Entry point: `lib/core/security/` —
`account_security_status.dart`, `recovery_code.dart`, `user_trust.dart`,
`confirmed_identity_store.dart`, `known_devices_store.dart`,
`security_prompt.dart` + `security_prompt_provider.dart`,
`security_providers.dart`, `new_device_alert.dart` +
`new_device_alert_provider.dart`, `unverified_device_warning.dart` +
`_provider.dart`, `password_strength.dart`, `prepared_uia_password.dart`,
`reset_confirmations.dart`, `restore_key_backup.dart`,
`screen_security_service.dart`, `security_emphasis.dart`,
`sensitive_clipboard.dart`, `verification_cancel_message.dart`,
`verification_signaling.dart`. UI lives in
`lib/features/settings/presentation/` (`advanced_security_page`,
`security_status_card`, `recovery_code_screens`, `why_security_page`,
`active_sessions_page`, `key_backup_management_page`,
`secure_backup_page`) and `lib/features/verification/presentation/`
(`verification_page`, `qr_scanner_page`, `approve_this_device_page`,
`confirm_person`).

Matrix's underlying security model (device keys, verification,
cross-signing, secret storage/key backup) is sound but is four mechanisms
a user has to learn and assemble into a story themselves. This app's
design keeps all of the underlying cryptography exactly as the `matrix`
SDK implements it and changes only what's named, when the user is asked,
and what it looks like.

## Architecture

`recovery_code_leak.dart` decides whether an outgoing message contains the
recovery code: ten or more consecutive words from the recovery wordlist, or
a base58 run shaped like a security key. `RoomPage`'s composer asks for
confirmation before sending one (`chats-messaging.md`). The threshold sits
under the code's own twelve words so a partly mistyped paste still trips it,
and the wordlist holds no short function words, so ordinary prose cannot
reach a run that long.

- **Every recovery, backup and approve-this-device screen is a
  `StepLayout`** (`app-foundation.md`); steps with fields or dense content
  use the compact circle. Two deliberate placements: on the screen that
  reveals the twelve words, Continue is the last item of the content, not
  a pinned action, so nobody continues without passing the words and the
  ways to save them; an error or checkbox that gates a pinned button is
  itself an action (the wrong-word message, "I've saved my recovery key"),
  so it shows above the keyboard next to the button it explains.
- **`SecureBackupPage.createBootstrap` is the test seam.** The default
  builds the SDK `Bootstrap` from `client.encryption`; a widget test has no
  encryption, so `secure_backup_page_test.dart` passes a fake and drives
  every state. A test that reaches `done` must start there: arriving via
  `onUpdate` starts the key restore and a sync.
- **`SecureBackupPage` drives the SDK's own `Bootstrap` state machine**
  (`package:matrix/encryption.dart` — the same one FluffyChat's Secure
  Backup setup uses) rather than reimplementing Secret Storage
  (SSSS)/cross-signing/key-backup logic. The app's UI only answers
  `Bootstrap`'s checkpoints (`askWipeSsss`, `askNewSsss`,
  `askUnlockSsss`, `askSetupCrossSigning`, `openExistingSsss`, `done`,
  …) — `BootstrapState` is matched exhaustively (no `default` case).
  A single recovery key is what cross-signing's private keys *and* the
  room-key backup both end up encrypted with — Secure Backup, cross-
  signing and key backup are one SDK flow, not three independent
  features, even though Settings still surfaces three focused entry
  points onto it.
- **One up-front choice reused for every later checkpoint.** "Restore
  with my recovery code" vs. "Replace with a new one" (the latter only
  shown when the account already has a key, e.g. set up earlier from
  Element) is asked once and auto-answers every subsequent "wipe this
  too?" checkpoint `Bootstrap` raises (cross-signing, key backup) —
  otherwise the user would face the same keep-or-replace question three
  times for what is really one decision.
- **`accountSecurityStatus(Client)`** (`account_security_status.dart`) is
  a pure, unit-tested function collapsing cross-signing state, key-backup
  state and pending-device state into one of five values, rendered as a
  single card with at most one button (see Data & State). Same shape as
  `mergeSessionInfo`/`session_info.dart`'s `sessionApproval` and
  `messageNotificationFor` — pure functions over SDK state, unit-tested
  without a live `Client`.
- **Verification** reuses one `KeyVerification` state machine and one
  screen (`verification_page.dart`) for three cases the SDK itself
  distinguishes and picks between: self-trusted, self-untrusted, and
  other-user (cross-user, reached from a contact sheet, over an in-room
  DM `m.key.verification.*` exchange). QR and emoji/SAS are two methods
  on the same flow, not separate features.
- **`UserTrust`** (`user_trust.dart`) computes a per-contact trust state
  (`noIdentity` / `unconfirmed` / `confirmed` / `confirmedWithPendingDevice`
  / `identityChanged`) from `DeviceKeys.verified`,
  `SignableKey.hasValidSignatureChain`, and this app's own
  `ConfirmedIdentityStore`. It is the source both the confirmed-person
  check mark and the identity-change banner read from.
- **`SignInAnotherDevicePage`** (`features/settings/presentation/`), from a
  row on Your devices: mints an MSC3882 login token
  (`issueLinkedSignInCode`, `core/matrix/linked_sign_in.dart`) behind the
  UIA password prompt, shows it as a QR and as grouped text with a
  countdown, blocks screenshots while open, and offers a new code once the
  five minutes are up. The countdown is its own widget so the QR is not
  repainted every second.
- **`KnownDevicesStore`**, keyed by user ID, is the shared seeding
  mechanism behind both the own-account "new device signed in" alert
  (`new_device_alert.dart`) and the per-contact "unvouched device"
  warning (`unverified_device_warning.dart`) — same write-before-show
  ordering, same in-memory-only dismissal model for both. The per-contact
  warning watches only people you share a *private* room with
  (`peopleWhoseDevicesWeWatch`) and its banner stays silent in public
  rooms: strangers' devices are noise, and tracking them costs a store
  write per stranger.
- **`confirmPerson`** re-reads `accountSecurityFactsOf` after the forced
  recovery setup returns and stops quietly if recovery or identity keys are
  still missing — Back from `SecureBackupPage` pops exactly like finishing
  does, and continuing would start a verification this device cannot sign.
  The setup step is injectable (`setUpRecovery`) for tests.

## Data & State

**`AccountSecurityStatus`** (five values, strict precedence order,
highest wins, card never shows two):

| Value | Meaning | Action |
|---|---|---|
| `deviceWaiting` | another of your devices is logged in but not approved | Review |
| `deviceLocked` | recovery exists, this device can't read history | Unlock them |
| `recoveryStale` | recovery code replaced; a device is now out of date | Fix |
| `noRecovery` | no recovery set up at all | Set up recovery |
| `protected` | recovery set up, this device holds the identity keys, nothing pending | *(no button)* |

The table is the card's urgency order. `accountSecurityStatus` branches
cheapest-discriminator-first instead — no recovery, then this device's
keys, then pending devices, then a stale backup — so each fact is read
once. The two orders agree: every pair the table ranks is mutually
exclusive on `recoveryExists` or `thisDeviceHasIdentityKeys` except
`deviceWaiting` vs `recoveryStale`, which both resolve to `deviceWaiting`.
Don't align one to the other without re-deriving the truth table.

Also requires `thisDeviceHasIdentityKeys` (`AccountSecurityFacts`) for the
symmetric case gate: a device that has never unlocked recovery has
`directVerified` nothing, so *every other device* reads as unapproved to
it, including correctly cross-signed ones (`SignableKey
.hasValidSignatureChain`'s final condition requires the master key itself
be `directVerified`). Without this gate, a freshly signed-in phone's
status card falsely accused every other device instead of asking to be
approved itself.

**`DeviceKeys.verified`** is `(directVerified || crossVerified) &&
!blocked`. The SDK always marks the *current* device's own keys
`directVerified` (it always trusts keys it holds) — that answers "do I
trust the keys I'm holding" (always yes), not "has the account vouched
for this device" (the question the devices screen asks). So the current
device's row must never read `DeviceKeys.verified`; `sessionApproval`
(`session_info.dart`) is the single verdict used for every row:

- current row → `thisDeviceHasIdentityKeys`, never `verified`, never
  `unknown`;
- another row, this device can judge (`canJudge` /
  `thisDeviceHasIdentityKeys`) → its own `verified`;
- another row, this device cannot judge → `unknown` ("Cannot check from
  this device") rather than a false "Not approved yet" on every row.

**Cross-signing status is two independent facts**, not one: whether the
*account* has cross-signing set up at all
(`encryption.crossSigning.enabled`) and whether *this device* holds the
private keys (`crossSigning.isCached()`). Key backup has the same
account-wide-vs-this-device split (`keyManager.isCached()`). Collapsing
either pair into one line loses the distinction the Advanced page exists
to show.

**Confirmation state (`UserTrust`)** depends on two pieces that must
both hold or neither works: `ConfirmedIdentityStore`'s own record (this
app's `confirmedIdentityKey`) *and* the SDK's own persisted
`identityDirectlyVerified` flag. `ConfirmedIdentityStore` also stores a
confirmation timestamp (entries from before it existed have none — never
backfilled, since that would misstate something the user may remember
doing differently).

**Recovery code (current design — see Key Design Decisions for how this
differs from the raw SSSS key):**

- Twelve lowercase words, space-separated, drawn from a fixed,
  checked-in 1296-word list (`assets/wordlist/recovery_words.txt`,
  generated by `tool/generate_wordlist.py`), ~124 bits, generated with
  `Random.secure`.
- Three properties enforced by generation and re-asserted by test
  against the *shipped* file: unique 3-character prefixes (autocomplete),
  minimum edit distance ≥ 2 between any two words (a typo can never
  silently become a different valid word), 4–8 lowercase-ASCII
  characters per word.
- Feeds the **existing** `Bootstrap.newSsss(phrase)` passphrase path — no
  protocol or server change. PBKDF2-HMAC-SHA512 derives the 32-byte
  secret-storage key; salt/iteration count live in server account data.
  The iteration count is hardcoded in `Ssss.createKey` — word count is
  the only strength lever this app controls.
- The base58 raw key (`OpenSSSS.recoveryKey`) still exists underneath
  either path (word phrase or raw key) and unlocks the same vault; it
  remains visible on Advanced.
- `normalizeRecoveryPhrase(String)` is the single frozen transform
  generation and entry must agree on forever: lowercase, map anything
  outside `a-z` to a separator, collapse runs, trim. Changing it silently
  invalidates every existing code (different derived key, vault refuses
  to open, no error, no recovery) — treat it as a one-way door, not an
  editable function.

## Communication

- **User-Interactive Auth (UIA)** (`client.onUiaRequest` /
  `Client.uiaRequestBackground`) gates every sensitive account action
  through this feature area: uploading new cross-signing keys during
  fresh Secure Backup setup, and (via the shared `askPasswordForUia`
  dialog, `uia_password_prompt.dart`) signing out other sessions and
  minting a sign-in code for another device, which Synapse always
  re-prompts for (`login_via_existing_session.require_ui_auth`). Current
  session's own sign-out skips UIA — the already-valid token is enough
  for `Client.logout()`.
- **Verification travels two ways**: to-device events
  (`m.key.verification.*`) for own-device flows, and in-room
  `m.room.message` events for cross-user (in-DM) flows — the latter means
  the timeline literally receives verification-protocol messages, which
  must be filtered out (see Gotchas).
- **`Client.verificationMethods`** must be non-empty
  (`{emoji, qrShow, qrScan}`) or the whole mechanism is inert in both
  directions: `KeyVerificationManager.handleToDeviceEvent` /
  `.handleEventUpdate` return early on `verificationMethods.isEmpty`
  (incoming requests never reach `onKeyVerificationRequest`), and
  `knownVerificationMethods` returns `[]` for outgoing requests, which
  the other side then cancels.
- **QR payload is binary**: `qrDataRawBytes` carries a `MATRIX` magic
  prefix and is not valid UTF-8. Scanning must read `mobile_scanner`'s
  `Barcode.rawBytes` (never `rawValue`); rendering must use `qr_flutter`'s
  `QrCode.fromUint8List` (never `QrImageView(data: String)`). Both
  string-based paths produce a code that scans cleanly and then fails
  verification.
- **Key backup is not auto-downloaded on unlock.** Unlocking Secret
  Storage grants *access* to the online key backup; it does not read it.
  Nothing in the SDK or this app calls `KeyManager.loadAllKeys()` other
  than `restore_key_backup.dart`'s explicit
  `restoreKeyBackupFromRecovery(client)`, which must run **before** the
  post-restore `oneShotSync` (not after) — syncing first just rebuilds
  room-list previews from the same still-undecryptable state. Absent
  that call, keys arrive lazily, one megolm session at a time, only when
  something tries to decrypt — and the triggering decrypt itself can't
  report success synchronously (`Encryption.decryptRoomEvent` kicks off
  `KeyManager.maybeAutoRequest` via `runInRoot` without awaiting it), so
  a naive retry-once approach always reports "still locked" on the first
  try.
- **`Room.onSessionKeyReceived` is per-room, not global.** A newly
  arrived key is announced there, not on `client.onSync`. An open
  `Timeline` recovers automatically because it subscribes to that stream;
  anything showing a room preview without an open `Timeline` (the room
  list) must subscribe itself to heal — one bulk restore is not the only
  source of a late-arriving key (a slow backup fetch or another device
  sharing a session both land the same way).
- **`oneShotSync` needs an explicit zero timeout** after a restore.
  `Client._innerSync` defaults a `null` timeout to a 30-second long-poll
  once already synced once — applying a recovery key doesn't itself
  produce a new server-side event, so the call would otherwise hang ~10s
  for nothing. Pass `timeout: Duration.zero` explicitly.

## Key Design Decisions

- **One status, one action.** `accountSecurityStatus` replaces "four
  sections of independent status" with a single five-value enum and a
  card with at most one button — the governing rule across this whole
  feature area: *never show a warning without exactly one button that
  resolves it*. Everything the old three-tile Security & Privacy page
  showed (session ID/key, cross-signing lines, key-backup
  version/algorithm/count) survives verbatim behind an **Advanced** row
  rather than being deleted — still useful for debugging, just no longer
  the first thing anyone sees.
- **Vocabulary is a deliverable, not polish.** One name for the whole
  mechanism (**recovery**), one for its secret (**recovery code** —
  collapsing the previously separate "security key" and "security
  phrase" into one generated word phrase), **device** never "session",
  **approve** for your own devices, **confirm it's really them** for
  people. `cross-signing`, `secret storage`, `megolm`, `fingerprint`,
  `bootstrap`, bare `verify` and persistent `unverified` are banned from
  every primary surface and survive only on Advanced.
- **Recovery code is a generated 12-word passphrase, not a raw key or a
  user-chosen phrase.** All three decode to the same 32-byte secret;
  the choice is only about what material feeds key-derivation. A raw
  base58 key can't realistically be transcribed or recalled without a
  password manager. A user-*chosen* phrase is typed zero times between
  setup and disaster and, unlike Signal's PIN or WhatsApp's backup
  password, has no server-side rate limiting to lean on — the vault is a
  file an attacker can grind offline, unlimited, against a permanent
  archive, so a chosen phrase's real strength is whatever the user
  picked. Twelve *generated* words (~124 bits) are uniform-strength and
  still paper/voice/typeable with no password manager. Raised from seven
  words (~72 bits) once it was clear the words are a *passphrase* that
  coexists with (and thus caps the effective strength of) the base58 key
  underneath, not an encoding of it — 72 bits is "beyond realistic," not
  beyond possible, against dedicated offline hardware. Twelve matches
  BIP39's own floor for something guarding irreversible loss.
- **No protocol/server change.** The generated phrase rides the
  existing `Bootstrap.newSsss(phrase)` path — this is a client-side
  decision about input material only, which is why it carries near-zero
  protocol risk despite being fully user-visible.
- **No forced migration, ever.** Rotating a recovery code is genuinely
  destructive (invalidates the old one, forces every other device to
  re-establish), so an account already holding a raw key or a
  user-chosen phrase keeps working unchanged; replacement stays an
  explicit Advanced action, never a side effect of an app update.
- **QR is the default, emoji the fallback**, one screen for both own-
  device and cross-user cases, never labeled "QR verification" in UI —
  "Scan to confirm."
- **Confirm people, not devices** — an unapproved-but-not-yet-vouched-for
  device belonging to an already-confirmed contact gets a passive
  line (it self-resolves in minutes, since the default sharing policy
  already withholds keys from it); an identity *change* gets a real
  in-timeline alert, since it silently voids a confirmation only the
  user can re-make.
- **Security copy earns its place only at a moment of consequence about
  someone specific**, never as ambient reassurance or a permanent
  score. Concretely: a confirmed-person check mark (receipt, not
  warning — shown once per screen, absence means nothing), one
  reassurance line in *empty* rooms only (never anchored into history,
  never on the room list), "Sent from a device X hasn't approved yet"
  only in the per-message long-press sheet (not a per-message timeline
  mark — tested and rejected in both polarities: an always-on mark
  becomes wallpaper and miscommunicates absence-means-unsafe; marking
  every unsigned-device message floods, since most contacts are never
  confirmed at all). No permanent device-count/fraction on a contact's
  trust row — reads as a permanently-failing score with no clean end
  state.
- **No shields, three visual states only**: neutral (nothing), confirmed
  (small muted check — reassurance, not achievement), attention (warning
  triangle, error colour, reserved for states that carry an action).
  Devices screen is the deliberate, sole exception: approved is
  green/not-approved is red using fixed colour values (not Material 3's
  brand-following `primary`/`tertiary` roles, which read as arbitrary
  hue on a non-standard seed) — justified because that screen's whole
  purpose is sorting into pass/fail, and nothing on it is pushed at
  anyone who didn't open the page.
- **"Encrypt to verified sessions only" is disabled, not removed**,
  until at least one device is verified — with verification broken
  (Phase 0 bug) or with zero verified devices, this toggle
  (`ShareKeysWith.directlyVerifiedOnly`) shares room keys with zero
  devices including the sender's own, silently making every outgoing
  message undecryptable for everyone.
- **Recovery key clipboard is sensitive.** `SensitiveClipboard`
  (`sensitive_clipboard.dart`) sets `ClipDescription.EXTRA_IS_SENSITIVE`
  (API 33+) and overwrites the clip after 90s, but only while it still
  holds the app's own text — there's no delete-the-clip API, so blindly
  clearing risks eating whatever the user copied since.
- **Local database is SQLCipher-encrypted** (`sqflite_sqlcipher`), key
  in `flutter_secure_storage` (Keystore-backed). Directly relevant here:
  the access token, Olm account pickle, and every inbound Megolm session
  live in that one file — this feature's cryptographic state has no
  protection independent of that encryption-at-rest layer.
- **Media/account recovery are two different things, both required.**
  The recovery code recovers *message history*; it does not recover
  *account access* (login). A forgotten password with no 3PID on file
  permanently and silently loses the account regardless of a saved
  recovery code. Needs verification: optional-email-as-3PID password
  reset is a scoped launch blocker but not yet built.
- **Colour is a budget, not a decoration — one shared attention system.**
  `security_emphasis.dart` (`attentionIcon`/`notEncryptedIcon`/
  `settledIcon`/`AttentionStripe`) replaced four surfaces that had each
  invented their own idea of "urgent." "Louder" is conveyed by the glyph
  being **filled** where every other icon in the app is outlined — so it
  reads as different in *kind* before it reads as different in colour,
  which also keeps it legible at small sizes and to someone who can't
  distinguish the colour — plus a 4px solid `error` stripe on the
  leading edge (full `error` fill reads as a crash screen;
  `errorContainer` alone is gentle enough to scroll past) and a filled,
  not text, resolving button. Deliberately no `settledColor`: giving the
  reassurance state its own colour would make the two ends read as one
  scale, so a room with no mark would look unsafe by contrast. This
  system is only safe to use because attention marks no longer compete
  with a permanent per-room lock badge (removed — see
  `rooms-membership.md`); with that noise gone, a mark this loud appears
  close to never for most accounts.

## Gotchas & Constraints

- `Client.uiaRequestBackground<T>` completes with `uia.result` before
  `UiaRequest._run` assigns it, so any non-void `T` throws "Null is not a
  subtype". Capture the response inside the request closure and call it as
  `<void>` (`issueLinkedSignInCode`).
- Two `onUiaRequest` listeners each open a password dialog. A page that
  listens (`ActiveSessionsPage`) cancels its subscription before pushing one
  that also listens (`SignInAnotherDevicePage`) and re-subscribes on return.
- `Room.lastEvent` is decrypted once, on first arrival over sync, then
  cached — it does not retry on its own. Retrying normally happens only
  inside an open `Timeline` via `room.onSessionKeyReceived`; nothing
  subscribes to that for a room that's never been opened, which is why a
  restore or a late key needs an explicit retry path in the room-list
  preview widget (`retryDecryptIfUndecryptable`,
  `core/matrix/retry_decrypt_last_event.dart`).
- `KeyVerification.canceledReason` is free text set by the *other*
  side and in practice mirrors the machine code — never render it raw.
  Read the **code**, not the reason, under one rule: never show a string
  starting with `m.`. An ordinary cancel and a genuine mismatch
  (`m.key_mismatch`/`m.mismatched_sas`/`m.mismatched_commitment`) need
  different copy — only a mismatch means the check ran and disagreed.
  Prose the far side actually wrote (not a bare code) is still passed
  through, since that's the one case this app can't say better itself.
- Room-based (cross-user) verification requests arrive as ordinary
  `m.room.message` events with sending-client fallback body text like
  *"...Apparently your client doesn't support this"* — which renders as
  a false failure message in the timeline even though verification is
  succeeding. `isVerificationSignalingMessage`
  (`verification_signaling.dart`) hides the whole `m.key.verification.*`
  family from the timeline and from `messageNotificationFor`, and is
  deliberately **not** gated behind the "show hidden messages" toggle
  (that toggle reveals things tidied away for noise; this event's body
  is actively wrong, not merely noisy).
- `ShareKeysWith.crossVerifiedIfEnabled` withholds keys from an unsigned
  device only when its *owner* has a master key at all — a contact who
  never set up recovery has every device (including a brand-new one)
  sent a full set of room keys, with no signal anywhere by default. This
  is the one real leak case `userTrustState` used to miss entirely
  (`noIdentity` returned before ever inspecting unsigned devices) — now
  covered by `unverified_device_warning.dart`, fired only on a device
  *appearing* (event, not persistent state — "this person has no
  identity" is true of most contacts most of the time and would be
  wallpaper as a permanent badge).
- Starting over on recovery (`wipeCrossSigning(true)` →
  `askSetupCrossSigning` with all three keys) generates a whole new
  cross-signing identity, not a re-wrap of the old vault under a new
  passphrase. Every confirmation the user made (a signature over the
  other person's master key from the user's *user-signing* key) is
  orphaned — still published, vouched for by nothing. Clearing local
  state on this path requires **both** halves or neither works:
  `ConfirmedIdentityStore.forgetAll()` and
  `CrossSigningKey.setVerified(false, false)` for every *other* user's
  master key (`forgetConfirmationsAfterIdentityReset`,
  `reset_confirmations.dart`) — clearing only the store leaves the SDK's
  own `identityDirectlyVerified` flag true; clearing only the flag
  leaves a stored key that later reads as a false `identityChanged`.
  Runs only on the wipe path, never on restore (which keeps the same
  identity, so clearing there would discard real, still-valid work).
- Testing gotcha (also in `CLAUDE.md`): do not stand up a real `Client`
  on `sqflite`/`sqflite_common_ffi` in widget tests (native FFI init
  hangs). Use `test/helpers/fake_matrix.dart`'s in-memory
  `FakeDatabaseApi`. Screens needing a fully synced `Room`/`Timeline`
  have no test coverage this way — most of this feature's logic is kept
  in pure, `Client`-state-in/value-out functions specifically so it can
  be unit-tested without that limitation
  (`accountSecurityStatus`, `sessionApproval`, `userTrustState`,
  `recovery_code.dart`'s normalisation/validation, `verification_cancel_message`,
  `verification_signaling`, `undecryptable_reason.dart`).
- `undecryptableReason` classifies by whether an *action* exists, not by
  a message's actual cause or timestamp — the SDK exposes no device
  creation time (`DeviceKeys.lastActive` moves, it isn't a creation
  stamp) and the underlying decryption-exception text isn't a reliable
  cause signal. A key backup that exists and this device hasn't opened
  is recoverable; anything else isn't — same signal `deviceLocked` uses.
- `Node.attributes` on sanitized HTML (`sanitize_message_html.dart`, used
  for `formatted_body` rendering, adjacent to this feature's trust model
  but not itself part of it) is a `LinkedHashMap<Object, String>` —
  namespaced attributes need `key.toString().toLowerCase()`, not a raw
  key comparison, or allowlist checks silently pass things like
  `xlink:href`. Documented here only as a nearby gotcha in the same
  security-hardening pass; the feature itself is content rendering, not
  verification/recovery.
- **A just-deleted device can still show up in the devices list.**
  `mergeSessionInfo` unions two sources (`/devices` and
  `client.userDeviceKeys`); a deleted device vanishes from `/devices`
  immediately but `userDeviceKeys` is only refreshed by
  `updateUserDeviceKeys()`, which itself is a no-op unless
  `DeviceKeysList.outdated` is set — and the only thing that sets it is
  a sync carrying `device_lists.changed`, which hasn't landed yet a
  moment after the deletion. `markOwnDeviceKeysOutdated`
  (`device_keys_refresh.dart`) forces the flag ahead of a refresh
  triggered right after a mutation, rather than waiting on that sync.
  The union itself is intentional — a device known to only one source
  still gets a row.
- **Ask for the UIA password before starting the destructive part of a
  recovery-code replace, not after.** `Bootstrap`'s `newSsss` only
  reaches the UIA checkpoint at the very end of the flow, so a naive
  screen order asks "are you really you?" only once the old code is
  already invalidated. `PreparedUiaPassword` (`prepared_uia_password.dart`)
  lets `_replaceExistingRecovery` collect the password up front and park
  it for `_handleUia` to consume later — the UIA protocol step itself is
  unmoved, only when the user is asked. Its `take()` is consume-once by
  design: handing a rejected password to a retry as well would silently
  resend the same wrong answer. Applies only to the replace path (both
  entry points); first-time setup has no existing code to invalidate and
  no destructive step to gate.

## Extension Guidance

- New account-security signals belong in `accountSecurityStatus` as
  another enum value with an explicit position in the precedence order
  — never as a second badge/line bolted onto an existing card. Keep it a
  pure function of `Client` state so it stays unit-testable without a
  live `Client`.
- New verification affordances (another QR/SAS entry point, another
  contact-sheet action) should route through the existing
  `verification_page.dart` / `KeyVerification` state machine rather than
  building a parallel flow — it already handles self-trusted,
  self-untrusted, and other-user cases uniformly.
- Any new secret-storage-derived material (a second passphrase-style
  credential, say) should reuse `Bootstrap.newSsss(phrase)` and the
  existing normalisation discipline rather than inventing a new
  derivation path — the whole reason the recovery-code work carries near-
  zero protocol risk is that it never touches the SDK's own crypto, only
  the input material.
- Never touch `normalizeRecoveryPhrase` after ship without a real
  migration path — treat it as append-only infrastructure, not editable
  logic.
- New "is this safe" UI should default to the three-state model (neutral
  / confirmed / attention) and the one-button-per-warning rule before
  reaching for a new visual language; the devices-screen green/red
  exception is deliberately singular and should not be treated as
  precedent elsewhere.
- Raw/advanced Matrix vocabulary and debug-shaped state (session key,
  cross-signing internals, key-backup version/algorithm) belongs on the
  Advanced page, not surfaced on a primary screen — extend Advanced
  rather than re-introducing that detail elsewhere.
- Full export/import of E2E room keys (standard encrypted megolm-export
  file format) is explicitly not built — neither the SDK nor
  `vodozemac`'s Dart bindings expose the encrypted file format, only the
  unencrypted per-session export string (`InboundGroupSession
  .exportAt`/`.import`). Building it means implementing PBKDF2 + AES-256-
  CTR + HMAC compatible with Element's own export format from scratch —
  scope it as its own security-sensitive pass, not a quick addition.

## Dependencies / Integration

- **`matrix` SDK** (`package:matrix`) owns all actual cryptography:
  `Bootstrap`/SSSS, cross-signing, `KeyVerification`, `KeyManager` (key
  backup), Olm/Megolm via `vodozemac`. This app never reimplements
  crypto — it only drives SDK state machines and reflects SDK-computed
  trust facts.
- **UIA** (`client.onUiaRequest`, `askPasswordForUia`) is shared
  infrastructure this feature uses for cross-signing key upload and
  session sign-out, and that other sensitive-action flows elsewhere in
  the app reuse the same way.
- **Room list / timeline (`event_display.dart`, room preview widgets)**
  depend on this feature's decrypt-retry and undecryptable-reason logic
  to show correct previews and cause-specific "can't be decrypted"
  copy.
- **Calls** (`CallSession`) independently reuses the same underlying
  device-trust primitives (`Client.getUserDeviceKeysByCurve25519Key`,
  `DeviceKeys.blocked`) to authenticate call-encryption-key senders —
  a parallel consumer of this feature's trust model, not part of it.
- **Notifications** — device sign-in alerts
  (`new_device_alert_provider.dart`) surface both as an in-app room-list
  banner and (via the notification-delivery path) a push notification;
  the two exist for different app states (foreground vs. backgrounded)
  and share one dismiss model.
- **`flutter_secure_storage`** backs the SQLCipher database key that
  protects this feature's persisted crypto state at rest; not part of
  this feature's own code but a hard dependency of its security
  properties.
- **Account recovery (password reset / 3PID)** is a *different*,
  currently unbuilt mechanism — see Key Design Decisions. Do not conflate
  the recovery code (message-history recovery) with account-access
  recovery when extending either.
