# Calls

## Overview

Voice/video calling, 1:1 and group, WhatsApp-like in UX. All calls —
including 1:1 — are routed through a configured SFU; there is no P2P mode,
by design. Signaling is a custom, simplified layer loosely modeled on
MatrixRTC (MSC3401), not a conformant implementation. Media runs through a
pluggable `CallEngine` abstraction, currently backed by Cloudflare Calls,
reached through the `zuno_calls` Synapse module so the app never holds SFU
credentials. On iOS, CallKit shows the ring and holds the call, and a closed
Zuno rings from a server VoIP push (iOS ring path below); Android uses a
`CallStyle` notification and a foreground service.

## Architecture

Three layers, matching the CLAUDE.md architecture map:

- **`CallSession`** (`lib/core/calls/`) — Matrix-side signaling and call
  lifecycle: sending/receiving invites, decline, ring timeout, membership
  publish/reconcile via `m.call.member`, the E2EE call key, hangup/teardown,
  and posting the timeline summary. Source of truth for "who is in this
  call" is `m.call.member` room state, watched via sync — not any local
  participant list.
- **`CallEngine`** — one interface (join/leave, mute/unmute, camera
  on/off, camera flip, screen share, switch voice↔video, participant/track
  streams) so call UI and signaling code are written once against the
  interface regardless of which media backend is active. `CloudflareCallEngine`
  (`flutter_webrtc`-backed) is the only implementation shipped; a LiveKit
  adapter was designed for but never built (see Extension Guidance).
- **`calls_module.dart`** — the URIs of the `zuno_calls` Synapse module
  (`/_synapse/client/zuno/calls/cloudflare/…`), a scoped proxy in front of
  Cloudflare's SFU signaling and TURN mint. The app sends the user's own
  Matrix access token as the bearer; Synapse validates it on every request
  and the module holds the actual Cloudflare credentials. Only signaling
  (SDP/track metadata, small JSON round trips at call setup) is proxied —
  RTP media flows directly between device and SFU, so the module is not in
  the media path and only affects call-setup latency.

`CloudflareCallEngine` carries real weight beyond wrapping an SDK: one
`RTCPeerConnection` + one Cloudflare session per call, with every
participant's tracks (local or remote) muxed onto that single connection as
transceivers — not one connection per remote participant. It owns
session/track fan-out, renegotiation, and failure recovery on top of
Cloudflare's lower-level session+track primitives (`CloudflareApiClient`).

Other integration points:
- `NegotiationLock` (`negotiation_lock.dart`) serializes every
  offer/answer round against the one shared `RTCPeerConnection` per call.
- `active_room_call.dart` (`findActiveRoomCall`) reads live `m.call.member`
  state directly to drive RoomPage's "call in progress" banner, independent
  of whether a ring invite was ever seen (covers missed ring, closed app,
  or joining a room mid-call).
- `call_member_state.dart` (`canPublishCallMemberState`) mirrors the
  homeserver's own power-level check for the `m.call.member` event type, so
  the app can refuse to ring/offer-to-join a user who could never actually
  publish membership, instead of connecting and then bouncing.
- **Call screens** (`lib/features/calls/presentation/`), always dark
  whatever the app theme. `CallPage` owns the session, the renderers and
  every side effect (foreground service, wakelock, speaker route,
  ringback, proximity, picture-in-picture), and only feeds values to
  `CallView`, a plain widget that decides the layout: a portrait stage
  (picture, name, one status line) while waiting and in a one-to-one voice
  call; their camera edge to edge with `VideoCallHeader`, the self view
  and floating buttons in a one-to-one video call, which also applies when
  only the other side's camera is on; a two-column `CallGrid` with
  everyone, you last, for three or more. `CallStatus` is calling,
  connecting, waiting, encrypting or talking; the lock and `CallTimer`
  show only while talking. `CallControls` is the one button row.
  `IncomingCallPage` shares `CallPortrait`.
- **Confirm-person pill** (`ConfirmPersonPill`, rule in
  `call_confirm_prompt.dart`): in a 1:1 chat's call, "Confirm it is
  really X" sits in the quality pill's slot and yields to it and to
  Reconnecting. `CallPage` offers it when the other person is unconfirmed
  or changed, this device can confirm, 30 s after they first appear (a
  timer flag, so tests need no clock), and not after "Not now" for that
  person (`CallConfirmPromptStore`, per device). It opens the why sheet
  (`security-verification.md`) from the `ValueListenableBuilder` context,
  which sits under the call's dark `Theme`; Confirm runs
  `confirmPerson(picturesFirst: true)` over the call.

**Platform seams** (`lib/core/calls/platform/`): what the OS shows or plays
for a call goes through six interfaces. Each has a `*For(capabilities)`
factory, with a provider over it, that checks `callKit` first wherever a
CallKit class exists (`PushRingBridge` checks `voipRing`); the Android flags
in parentheses are never flipped on iOS (`app-foundation.md`):

| Seam | Methods | Android | iOS |
|---|---|---|---|
| `IncomingCallPresenter` | `showIncoming` (→ `RingOutcome`), `cancelIncoming`, `activeRing` | `zuno/call_style` CallStyle notification with its native tone and vibration (`nativeIncomingRingUi`) | `reportIncomingCall` / `endIncomingCall`; `activeRing` is always `null` |
| `OngoingCallPresenter` | `start`, `stop` | `CallForegroundService` (`callForegroundService`) | No-op: `systemCallSyncProvider` drives CallKit |
| `RingbackTonePlayer` | `start`, `stop`, `restartForRouteChange` | `ToneGenerator` (`nativeRingbackTone`) | Native `CallRingback` |
| `SystemCall` | `begin`, `connected`, `setMuted`, `upgradeToVideo`, `end` | No-op | `startSystemCall` … `endSystemCall` |
| `CallAudioOutput` | `read`, `apply`, `watch`, `unwatch` | flutter_webrtc `Helper` + `ondevicechange` | `audioRoute` / `setAudioRoute` + `audioRouteChanged` |
| `PushRingBridge` | `updateIncoming`, `bindIncoming`, `endUnbound`, `declineSent` | No-op | The same calls on `zuno/calls` (iOS ring path) |

- Ringback has exactly one gate: its factory. Both players re-check the
  Ringtone setting. `fullScreenIntent` gates only the full-screen
  permission UI, never the presenter.
- **A presenter that really rings extends `RememberingIncomingCallPresenter`**:
  it writes the ringing-call store before `presentIncoming`, so a platform
  presenter cannot forget the store that `main.dart` (`pendingRing`) and
  the push handler read. Written after, a Decline or summary in the gap
  would miss the cancel and leave the ring sounding. `forgetAndDismiss`
  drops the record with the dismiss: on Android natively, in one
  remove-if-matches step with the ring (a record for another call younger
  than 45 s survives); Dart clears it only when that call fails. The CallKit
  presenter remembers nothing, like the no-op: a non-null `activeRing`
  would push `IncomingCallPage` over CallKit's own ring.
- **A ring is idempotent per call id, across push and sync.** Rings are
  serialized per isolate, and a call already ringing (presented here within
  `SystemRing.lifetime` and still remembered, or the active ring) answers
  `shown` without ringing again. A ring shown for a call that resolved
  meanwhile is taken back (`filtered`).
- **A ring cancel names its call** (`cancelIncoming(roomId:, callId:,
  end:)`), so one call's end never takes down another call's ring: the
  remembering presenter leaves a stored ring for another call up, and
  CallKit ends only the named call, with `end` (`RingEnd`) as its reason.
- **CallKit's answer and decline** arrive as `answerCall` / `declineCall`
  on `zuno/calls` with `{roomId, callId, callerId, isVideo}` and join
  `onAction`, like notification buttons; on iOS `RingCoordinator` takes
  them (iOS ring path). One that arrives before anything listens (cold
  start) is held for `takeLaunchCallActionFromNotification`.
  An open `IncomingCallPage` runs the action itself (the router defers to
  it) and cancels the presenter as it closes, so two ring UIs never both
  stay up.
- Decline routing (the live routes, the headless response handler)
  deliberately stays in `call_notification_service.dart`: presentation and
  routing never travel together.

**CallKit (iOS)**: native owns CallKit and the audio session; Dart drives
both over `zuno/calls` (`CallsChannelPlugin.swift`).
- `CallKitCenter.swift`: a process-wide singleton with a lazy
  `CXProvider`. Its configuration is re-set before every report and start
  (Apple DTS's workaround for a call whose audio session never activates),
  which also picks up the Ringtone setting. Every call's UUID, incoming or
  outgoing, is UUIDv5 over `room_id + "\n" + call_id` (`CallIdentity`, a
  fixed namespace, vectors in `call_uuid_v5.json`), so sync, push, the
  extension and Dart name the same call. An ended one leaves a tombstone
  (last 64) and a resolved ledger entry: a late report of it is `filtered`,
  never a second ring. Actions the app requests are tagged, so only the
  user's own taps reach Dart.
- Native events queue (32, oldest dropped) until Dart pulls them:
  `CallNotificationService.initialize` sends `resetSystemCalls` (ending
  calls a previous Dart owned), then `RingCoordinator` calls
  `takeCallEvents`, which also replays each call still ringing.
  `audioRouteChanged` and a pushed ring's `ringing` are sent live only
  (the replay covers the ring).
- `CallAudio.swift` owns the one audio session (decisions below) and
  `CallRingback`, a synthesized 425 Hz tone that plays only once the
  session is active; the pre-call category comes back after the last
  call. Without CallKit (Simulator, iOS app on Mac) calls run a
  self-managed session.
- `systemCallSyncProvider` (`system_call_sync.dart`, watched by the router)
  binds `activeCallProvider`'s session to its CallKit call: begin
  (adopting the ringing call, answering it if still ringing), connected on
  the first remote, mute both ways, video on the first camera, end with the
  session's reason. The hang-up button's `byUser` end is requested as a
  `CXEndCallAction`; any other end is reported.
- A ring report returns `shown`, `filtered` (Focus, block list, tombstone:
  nothing shows) or `unavailable` (`RingCoordinator` falls back to
  `IncomingCallPage`). A group call rings under the room's name. The name
  follows the preview level (`notifications.md`): "Zuno call" at Nothing.

### Live routes and declines

**A Decline, Reply or Mark as read tap goes to the running app first**
(`live_isolate_route.dart`). The app registers two named ports,
`zuno_call_decline_port` and `zuno_message_action_port`, when `main.dart`
initializes `CallNotificationService`, and re-claims them on every resume
and every ring it presents (`reclaimLiveRoutes`). A sender gives up at the
first step that misses its bound:

| Step | Bound |
|---|---|
| `ping` answered by `pong` | 2 s, the receiver's freshness window |
| `accepted` | 4 s |
| `done` | 25 s |

- The receiver refuses a malformed message or one older than 2 s. With
  nobody listening yet (cold start) the app accepts and holds it, and drops
  held entries older than 25 s once a listener arrives: their sender has
  done the work itself by then.
- Why the probe waits the full 2 s: a busy but alive app read as gone hands
  the work to a second client, whose stale in-memory Megolm outbound session
  can reuse a message index.
- Every path of one action carries one txid, so a hand-off that timed out
  and its fallback never send twice: one per Reply or Mark as read tap (the
  app performs a txid once), `zuno-decline-<callId>` for a decline.

**Where a Decline goes:**

| Stage | Behavior |
|---|---|
| flutter_local_notifications' action engine (`runHeadlessCallDecline`) | Per-run wake lock; stops the ring and marks the call resolved; hands the decline to whoever holds the decline route. Nobody takes it: opens its own client, retries the hand-off for about 6 s when the lease is denied, sends with retries (2 s, 5 s) |
| Push engine's ring hold (`awaitHeadlessDecline`) | Claims the decline route only when nobody holds it or its holder answers no ping. Holds up to 45 s, checking every 3 s that the route is still its own and the ring still shows (5 s grace once it does not). Sends through its burst client; a denied lease hands the decline to the app's route. Reports `done` only once sent or handed over |
| The app (`HeadlessCallDeclineNotifier`) | Cancels the ring (`declinedElsewhere`), marks the call resolved, sends with retries, then reports `done` |

### iOS ring path (`voipRing`)

With Zuno closed the server rings; a running app still rings from sync, on
the same CallKit UUID. Why from the server, and what was rejected:
[ios-push-and-ring.md](../decisions/ios-push-and-ring.md).

1. **Server**: the `zuno_push` Synapse module (its own repo) watches
   `m.call.member` and posts one sealed blob per device to Sygnal
   (`im.zuno.chat.ios.voip`, `.ios.dev.voip`; topic `im.zuno.chat.voip`),
   which APNs delivers as a VoIP push.
2. **Native**: `PushRingHandler` (PushKit) opens the blob, `RingDecision`
   picks the action, and `CallKitCenter.reportPush` reports it to CallKit
   before PushKit's completion runs. A shown ring prewarms the app engine
   (`EngineHost.startForRing`, `app-foundation.md`).
3. **Dart**: `RingCoordinator` (`ring_coordinator.dart`, kept alive by
   `pushRingServicesProvider`) takes the ring, the answer and the decline.
   Android keeps the `RoomListPage` path.

**Every push is reported.** iOS kills an app that returns from a VoIP push
without reporting a call (MetricKit code `0xbaadca11`, in the diagnostics),
so a push that must not ring is reported as a "Zuno call" placeholder and
ended at once. Only iOS 26.4's `mustReport == false` lets one complete
unreported.

**The blob** (`VoipBlob`): ChaCha20-Poly1305 under this device's 32-byte
key, padded to 512 or 1024 bytes, so Apple learns only that a call arrived.
It carries room, call, caller, names, kind and timestamps, and expires 45 s
after `min(sent, received + 30 s)`, judged on the server's clock (`meta`'s
offset).

| Push | Ring decision |
|---|---|
| New call | Rings, named from the room's title file (DM partner or room title), else the blob's names; until the blob expires, 55 s at most |
| A call CallKit already tracks | Updates its name and video flag |
| Stale, resolved, own, or a canary | Reported, then ended |
| Another call ringing or active | A placeholder, then ended |
| Unknown key or version | A generic "Zuno call" for Dart to bind (45 s) and a re-registration; from the third in 10 min, ended as failed |
| Forged (the tag fails) | Reported, then ended as failed |
| Before first unlock | A generic ring, silent if Ringtone was off (`ring.flag`); the blob is kept and opened once protected data arrives |
| Signed out, no session | Reported, ended, and VoIP pushes turned off |

**Registration** (`VoipRegistration`, `zuno/voip`): the PushKit token and
key go up with `PUT voip` at sign-in, on resume once the token or key
changed or 6 h passed, and on Retry, never gated on notification
permission. A refusal
shows "Calls may not ring while Zuno is closed" (`notifications.md`). The
key is in the Keychain (`im.zuno.chat.voip`, the app only), new per session
and per token not yet acknowledged; the previous one still opens blobs for
24 h after the new one is acknowledged. Sign-out sends `DELETE device`,
deletes the key, ends every call and stops VoIP pushes. Prefs:
`push.voip.session`, `push.voip.acked`.

**Binding a ring to its call:**
- A generic ring carries no call. The coordinator binds it
  (`bindIncoming`) to the newest call another member started in the last
  45 s (`m.call.member`), checked on each sync and the next invite, or ends
  it after 20 s (`endUnbound`).
- A sync invite for a call a push already rang only updates its name
  (`updateIncoming`); any other one rings through CallKit as before (call
  waiting applies; `IncomingCallPage` when CallKit is unavailable).
- Native rings reach Dart as `ringing` with a `source` (`NativeRing`:
  `sync`, `push`, `generic`, `bfu`).

**Answer and decline of a pushed ring:**
- Dart first reads the caller's `m.call.member` from the server
  (`checkCallLiveness`, 5 s). A call no longer listed ends as remote-ended;
  a timeout or error goes on, since the blob was authenticated. Why: local
  state is stale after suspension.
- CallKit's answer is held until Dart reports the call connected, or 2 s
  before the action times out. Dart has 45 s to take it over (30 s for a
  sync ring), else the call ends as failed: the engine may be starting cold.
- An answer before first unlock that never binds ends as failed and posts a
  "Missed call" notice: "Unlock this device after a restart to answer
  calls."
- A ringing pushed call holds a 30 s background task, so the engine can
  start and sync; a decline holds 25 s until Dart has sent it
  (`declineSent`).

**The call ledger** (`ledger` in the notify App Group): native records each
incoming CallKit call's state (`ringing`, `answered`, `ended`, `declined`,
`missed`; source `push` or `sync`; last 64) and posts
`im.zuno.chat.ring.changed`. A resolved entry stops a late push from
ringing; the extension reads it to tell whether CallKit rang.

**The extension's fallback ring** (`NsePipelineCalls`): the invite's message
push reaches the extension too. With no ledger entry for the call it waits
up to 8 s for CallKit to ring, then shows a time-sensitive "Incoming voice
call" (`fallback_ring.caf`, or `silent_ring.caf` with Ringtone off) and asks
the module's `ring/status`, within 23 s of starting:
- A ring the module sent gets until 8 s after its send time.
- `failed`, `no_token`, an unknown answer and `suppressed` for
  `voip_failing` keep the fallback.
- Any other suppression, `pending`, or the ledger catching up turn it into
  a quiet "Voice call" line.

Once CallKit shows a pushed ring, the app removes that fallback and the
room's floor lines from the last 20 s (`RingFloorSweeper`). A missed or
declined summary the extension sees ends that ring in the app
(`im.zuno.chat.calls.changed`), ahead of Dart's sync.

## Data & State

**Call lifecycle** (`CallSessionPhase`): `connecting` → `active` → `ended`.
A session is created either via `CallSession.forIncoming` (callee) or
`startOutgoing` (caller); both return a `connecting`-phase session
immediately and run the actual connect sequence (permissions, engine
build, join, publish membership) in the background — the UI never blocks
on that sequence to render (see Gotchas: caller-view lag).

**Membership** is `m.call.member` room state, one entry per device
currently in the call, carrying `fociInfo` (`audioMuted`, `videoEnabled`,
`lowBandwidth`, `encrypted`). This is the single source of truth for
participant presence — not any client-local roster — republished on a 50s
timer (each entry good for a 120s TTL) plus on every user-visible state
change. Engine-driven changes (quality tier, rejoin, key arrival) publish
at once via `localStateChangedStream`; user toggles (mute, camera,
voice↔video) go through `refreshMembership`, a leading-and-trailing 1s
window: the first toggle publishes immediately, later toggles inside the
window coalesce into one trailing publish of the final state, skipped by
the fingerprint check if nothing changed. A state event is permanent room
history, so the window caps a mashed button at two events per quiet
second.

**Signaling events** ride ordinary `m.room.message` events with custom
msgtypes (`im.zuno.call_invite`, `im.zuno.call_decline`,
`im.zuno.call_summary`), the same pattern voice messages use for custom
msgtypes — this flows through existing pagination/timeline plumbing for
free. `call_invite`/`call_decline` are filtered out of the rendered
timeline (like edit-relation events); only `call_summary` renders, as a
"Missed voice call" / "Video call · 5:32" tile. `call_summary` is sent
unconditionally on every way a call ends, so it's the one signal both
sides can rely on (used by the callee's ring page to detect an early
caller-cancel, and by the caller to detect a late decline).

`call_decline` and answered (`ended`) summaries carry an `m.reference`
relation, to the caller's and to this device's `m.call.member` event
respectively (`callMembershipEventId`, `_membershipEventId`), so the
`im.zuno.reference` push rule keeps them off the push path: nobody needs a
notification for them. Missed and declined summaries have no relation and
still push, because the declined one is what stops a ring on the callee's
other devices. With no membership event to point at, an event goes out
without the relation and pushes as before.

**End reasons** (`CallSession.endReason`) distinguish declined / missed /
declinedByThem / failed / normal hangup — `failed` carries a user-facing
`failedMessage` (e.g. permission-denied) surfaced via snackbar.

**The ringing call** is one singleton per isolate on both platforms:
`SystemRing` (`system_ring.dart`) holds the call ringing, for 60 s at most.
Every ring path sets it (the push handler too, in whichever engine handles
the push), the Android ring page for as long as it is up, and only that
call's id clears it. Call waiting, `ringElsewhereProvider` and the
background-sync rule read the app's.

**Resolved calls** never ring again: a summary, a decline, an answer or
decline on another of my devices, or an unanswered ring end marks one.
Every isolate goes through `markCallResolved`/`isCallResolved`
(`resolved_call_ids_store.dart`): one prefs key per call
(`calls.resolved.<callId>`, kept 5 min, newest 32), serialized per isolate,
with the app's `resolvedCallIdsProvider` as the in-memory mirror. One key
per call, because a lost id rings a finished call again, and two isolates
rewriting one shared value could drop each other's ids. Several paths mark
the same call, so `markResolved` ignores a known id (no rebuild, no write).
A summary push takes its call's ring down no sooner than 3 s after it was
posted, but marks the call first, so a redial in that window rings; its
cancel names the call, so the redial's ring stays.

**Group-call rules**, since >2 participants breaks assumptions 1:1 calls
could get away with:
- Leaving is not the same as ending. The timeline "ended" summary is
  posted by whoever is the *last* participant out (tracked as "any other
  participant still known to be in the call at hangUp time"), regardless
  of caller/callee role — not hardcoded to the original caller. (One
  known unclosed race: the last two participants hanging up in the same
  instant.)
- The E2EE call key (below) is relayed by *any* session that already
  holds it to a newly-discovered device, not only the original caller —
  same caller-only assumption, same fix.
- "Was this call ever answered" is tracked by `_everHadRemote` (set once,
  never cleared) rather than "is `_knownRemote` currently empty" — the
  membership-reconcile cleanup that removes a departing participant runs
  *before* the auto-hangup path calls `hangUp()`, so an empty-check at that
  point is always true and mis-reports every auto-hangup as "missed" even
  when the call was fully conducted.
- **At most 6 participants** (`maxCallParticipants`, distinct users),
  enforced client-side only — the module has no notion of which call a
  session belongs to. Everyone is still rung; the first 6 in win.
  - `CallSession.accept()` refuses when 6 others hold membership
    (`isCallFull`), before permissions or an engine, ending `failed` with
    the call-full `failedMessage`.
  - Simultaneous joins can still reach 7, so each membership carries a
    fixed `created_ts` (set once per session). On every reconcile a
    device ranked 7th or later by (`created_ts`, user id)
    (`isOverCallCapacity`) hangs up with the same message. Each device
    judges only itself, so no coordination is needed. The check runs
    after the membership loop so `_knownRemote` is populated and no
    "ended" summary is posted. Missing `created_ts` (older builds) reads
    as 0, so they are never evicted; ranking trusts device clocks.
  - Every entry point pushes `CallPage` before calling `accept()`, so a
    refusal ends the session before the page mounts. `CallPage.initState`
    therefore finishes an already-ended session at once, skipping
    `_init()` (no permission prompt).

**E2EE for calls**: one random 32-byte key per call
(`CallSession._generateCallKey`, `Random.secure()`), applied via
`flutter_webrtc`'s `FrameCryptor`/`KeyProvider` (insertable-streams-style
per-frame AES-GCM, same technique LiveKit/Zoom/Meet use with an SFU in the
path). Deliberately **not** the room's Megolm session — different
construction (message-ordered ratchet vs. flat AES-GCM with its own
loss-tolerant key-ring), and Megolm's key is scoped to *room* membership
(anyone with key-backup access), not *call* membership. The key is sent
to each remote device as discovered, Olm-encrypted over to-device
(`client.sendToDeviceEncrypted`, `im.zuno.call.encryption_key`) — never
the room event stream, never plaintext to the homeserver — retried up to
three times with backoff (300ms base, 1s cap) per device; a receiver
keeps only the first key it gets, so a retried duplicate is harmless. One
key per call, generated at start, discarded at hangup — deliberately
never rotated on membership change: rotating would mean re-distributing
a new key to everyone still present every time someone leaves, and
skipping it is what lets someone who leaves and rejoins simply be
re-sent the *same* key rather than needing a fresh handout. A late
joiner who missed the original handout (e.g. joined after the original
key-holder left) may simply never receive a key. A device that re-joins
mid-call under the same device id (app restart, new `sessionId` inside
the old 120 s membership TTL), or a participant who fully leaves and
later rejoins (re-detected as a new device once dropped from
`_knownRemote`), is re-sent the key by whoever currently holds it —
tracked per device as the last `fociActive['sessionId']` seen, since
"already known" alone would leave it "Encrypting…" forever. Media is
pulled from a remote only when *both* sides report `encrypted`
(`planRemoteTracks`), never on "our flags match": two unkeyed peers that
pull each other start decoding plaintext, and the first key to land then
flips one sender to ciphertext while the other's receivers are still
unwrapped — the decoder wedge this gating exists to prevent. Local mic
and camera tracks are kept `enabled = false` until their own sender's
frame cryptor exists (`_applyLocalTrackState`, the single writer of
`track.enabled`), so a callee never pushes plaintext to the SFU during
the 0.5-2 s the key is in flight. The cryptor, not the key, is the gate
because the video sender has no track until the camera comes on and the
native factory dereferences `sender->track()`: a track-less sender is
never wrapped (`_wrapSender` returns), the wrap happens right after
`replaceTrack`, and the track only enables once it has landed. A peer that never reports `encrypted`
gets no media and shows "Encrypting…"; the local side shows the same
state until its own key lands. In a one-to-one call that is the call's
status line (either side unkeyed counts, and a view with no local
participant never claims the lock); in a group it is a badge on the tile
it concerns. Stuck for 8 s, `EncryptingLabel` adds: "Still encrypting. If
this continues, hang up and try again." The 8 s count from when
encrypting began (`encryptingSince`), so a layout change does not restart
them. There is no unencrypted fallback and no red banner.

## Communication

**Cloudflare Calls dialect via the Synapse module.** `calls_module.dart`
resolves `_synapse/client/zuno/calls/cloudflare/{sessions/…,turn/credentials}`
against `client.homeserver` exactly as the SDK resolves `_matrix/…` — the
`.well-known`-*resolved* base, not the address typed at login, and a path
prefix behaves the same for both. `CloudflareApiClient` keeps Cloudflare's
own paths/JSON verbatim; the module is a signaling proxy with
`/apps/{appId}` filled in server-side, so engine-side negotiation logic is
unchanged by the proxy — only base URL and auth. Auth is the Matrix access
token (`bearerAuthorization`, which refreshes a token about to expire
first); Synapse checks it on every request, so there is no stored
credential and no remote-logout window. A 401 is final, never retried. Module errors are Matrix JSON; the only field the app reads is
`retry_after_ms` on a 429.

**Negotiation roles differ by direction** — publish (local
mic/camera → offer → `pushLocalTracks` → answer) is standard
offerer-us/answerer-Cloudflare WebRTC; **pull** (subscribing to another
participant's tracks) is the reverse: Cloudflare's `tracks/new` response
for a pull carries an *offer*, so the correct sequence is
`setRemoteDescription(Cloudflare's offer)` → `createAnswer()` →
`setLocalDescription` → PUT the answer to `/renegotiate`. A pull that
can't be completed (offer not applied, no answer, `/renegotiate` refused)
is forgotten locally and its mids force-closed on the SFU (`tracks/close`,
`force: true`), so the next membership sync pulls it again. Left marked as
pulled, that person stayed silent and invisible until they rejoined.

**ICE gathering is not trickle** on Cloudflare's REST signaling — there's
no endpoint to send candidates as they arrive, so an offer must already
carry them. Negotiation therefore waits for gathering to reach an idle
cutoff (genuinely complete, or ~500ms with no new candidate) before
sending, with a 3s hard ceiling as backstop for a stalled network.

**Retries**: `lib/core/errors/backoff.dart` (`backoffDelay`, full-jitter
exponential) + `retry_backoff.dart` (`retryWithBackoff`, whose `retryAfter`
hook lets a server-stated wait replace the backoff, clamped to `maxDelay`),
wired into the calls-module HTTP clients only — nothing else in the app
retries automatically.
- `CloudflareApiClient._send` retries `SocketException` (request never
  reached the module) and a 429, waiting the module's `retry_after_ms`: the
  module refuses before calling Cloudflare, so a 429 is retry-safe. Any
  other non-2xx status or `http.ClientException` is **not** retried —
  `/sessions/new` and `/tracks/new` create resources, so retrying a request
  that may have already landed risks a duplicate session/track server-side.
  Kept short (3 attempts, sub-2s ceiling) since these calls sit inside live
  SDP negotiation. Every request carries a 15 s deadline, above the
  module's 10 s upstream timeout, so a dead socket fails the join instead
  of hanging it forever.
- `fetchCloudflareIceServers` (TURN) retries transport failures
  (`SocketException`, `http.ClientException`) and 429 only. A 5xx is
  final: the module already retried Cloudflare twice on that path (up to
  3 × 10 s server-side), and app-side retry only multiplied that wait.

**TURN**: `resolveIceServers` (`ice_servers.dart`) mints credentials
through the module concurrently with `sessions/new` — the engine takes a
`Future` of ICE servers and awaits it only at `createPeerConnection` — and
caps the mint at 5 s; a failed or late mint yields an empty ICE list rather
than failing or delaying the call — TURN only matters for the subset of
networks that can't manage a direct/STUN-assisted path. (A selectable homeserver-vs-Cloudflare
TURN provider was built and then superseded/pinned to Cloudflare only,
with the picker UI disabled — see Key Design Decisions.)

**Reconnection**: `disconnected` starts a 5s grace period; `failed`, or
grace expiry, triggers up to 3 full rejoins — new session and peer
connection, local tracks re-added, remotes re-pulled — with jittered
backoff (1s base, 4s cap). A remote whose `sessionId` changes has its old
pulls closed and is pulled again. After 3 failures the session ends the
call with "Connection lost". Cloudflare sessions can't ICE-restart, so a
rejoin is the only path back.
- Negotiation code resumed mid-rejoin captures the peer connection and
  session id it started with, and re-checks `_isLiveConnection` after
  every await — a stale round-trip can't touch the connection a newer
  rejoin already replaced.
- The old peer connection's callbacks are detached before it's closed; a
  rejoin that finds the engine already left closes the connection it just
  opened rather than leaking it.

**Incoming call delivery**: live sync (`client.onTimelineEvent`) drives
ringing while the process is alive; under the background-sync delivery
mode a persistent foreground service keeps the process from being
suspended. Push (FCM, the default, or UnifiedPush)
reaches the app's engine while it runs and a push engine otherwise
(`notifications.md`), so a killed process still rings. A
ring notification carries its own Accept/Decline actions and a
full-screen intent; `CallForegroundService.kt` backs the persistent
in-call notification once active (Android requires a real foreground
service for background mic/camera capture). On iOS a running app rings from
sync and a closed or suspended one from a VoIP push (iOS ring path).

**Ongoing-call notification actions**: its `CallStyle` Hang up button
broadcasts to `CallActionReceiver`, which invokes `hangUpCall` on the
`zuno/calls` channel (held statically by `MainActivity` for the engine's
lifetime); `CallNotificationRouter` then hangs up `activeCallProvider`'s
session. Deliberately *not* the headless `ActionBroadcastReceiver` route
the ring's Decline uses — that boots a second Flutter engine, whereas
hangup needs the live session in the main isolate for media teardown,
membership retract and the summary event. Safe because `CallPage` is
`canPop: false`: the session is alive for as long as the notification
exists. If the engine is gone anyway, the receiver stops the service
instead, so a stale notification can't outlive its call.

## Key Design Decisions

- **SFU-only, no P2P, permanently.** Group calls need the SFU stack
  regardless, so a separate P2P stack would only serve the narrower 1:1
  case; on mostly-cellular/CGNAT Android networks, direct P2P often falls
  back to TURN relay anyway. Neither Cloudflare Calls nor LiveKit relay
  media peer-to-peer even for 2 participants — both always terminate each
  client's connection at the provider's server — so there's no "P2P via
  the SFU" shortcut either.
- **The video transceiver is published at join, camera or not.** A voice
  call publishes a track-less `sendonly` video transceiver; voice→video
  is `sender.replaceTrack`, and camera-off is `track.enabled = false`.
  The client therefore never sends a second offer during a call. That is
  deliberate: a local re-offer while a remote's video is flowing makes
  libwebrtc recreate that receive stream, and a packet landing in the gap
  trips its unsignalled-SSRC handler, which nulls the stream's sink for
  good (frames keep decoding, nothing renders: the "frozen remote, fine
  audio" symptom). The receiving side never closes a pull for a
  camera-off either: `planRemoteTracks` only decides what to pull, and
  the tile is hidden from `videoEnabled`.
- **No mid-call auto-downgrade to voice when every camera is off.**
  Considered and declined: needs distributed coordination with no single
  authority (each device only knows its own camera state plus what others
  last published), trades instant camera-re-enable for a renegotiation
  delay, and risks flicker on near-simultaneous toggles — for savings
  already mostly captured by never pulling a camera-off video.
- **Voice↔video switch reuses the camera toggle**, overloaded by call
  kind, rather than a separate button — two near-identical camera icons
  read as ambiguous (mistaken for screen share) in testing. There is
  deliberately no UI path to go from video back down to voice mid-call.
- **Screen share is a deliberate no-op.** Android capture needs its own
  MediaProjection consent flow and a `mediaProjection`-typed foreground
  service; `CallForegroundService.kt` only declares `microphone|camera`.
- **`/sync` stays alive while a call is active or a ring is up, even
  backgrounded**: remote departure, declines, an answer on another device
  and key delivery arrive only through sync. The rule, including the
  CallKit lock-screen case, is in `app-foundation.md` (backgrounding
  pauses `/sync`).
- **Voice calls turn the screen off at the ear** with the system dialer's
  own mechanism, no sensor plumbing in Dart: Android's
  `PROXIMITY_SCREEN_OFF_WAKE_LOCK` (`MainActivity.setProximityScreenOff`),
  iOS proximity monitoring (`ProximityScreen`, off only once the sensor
  clears). `call_proximity.dart` decides: wanted only for a voice call on
  the earpiece (not speaker or a headset, as the dialer does) and not
  finished (ringing counts). `CallPage` syncs it on init, every route
  change, voice→video and finish; native also releases it with the engine
  and the Android activity.
- **The audio route is earpiece, speaker, wired headset or Bluetooth**
  (`call_audio_route.dart`, pure). A call starts on a connected headset
  (Bluetooth first), else the earpiece for voice and the speaker for
  video; switching voice→video moves the earpiece to the speaker.
  `CallPage` re-reads the outputs on every device change
  (`CallAudioOutput.watch`): a newly connected headset takes the sound,
  and losing the one in use falls back to another headset, else the
  starting route. The speaker button toggles speaker ↔ the preferred
  headset, else earpiece.
- **Android routes through flutter_webrtc** (`WebRtcCallAudioOutput`):
  outputs are named `bluetooth` / `wired-headset`, and AudioSwitch fires
  `ondevicechange` on every device or selection change. Headsets are
  chosen with `selectAudioOutput`: AudioSwitch keeps the last
  user-selected device while it stays connected, so after
  `setSpeakerphoneOn(false)` picked the earpiece, a headset connecting
  later never took over on its own.
- **iOS routes natively** (`CallKitCallAudioOutput`): `CallAudio` reads
  headsets from the session's port types and reports each route change
  (`audioRouteChanged`), so the in-app button follows CallKit's own
  speaker button. Native picks the starting route; Dart applies only taps
  and headset changes (CallKit decisions below).
- **Picture-in-picture follows the other side's camera only.** Android
  system PiP (`MainActivity.kt`, `supportsPictureInPicture` in the
  manifest) is eligible while any *remote* participant has video on; the
  local camera never matters, since the window exists to keep watching
  them. `CallPage` pushes eligibility plus the remote frame's aspect
  ratio (`call_picture_in_picture.dart`: 3:4 until the first frame,
  clamped to Android's 2.39:1 limit) over `zuno/calls` on every
  participant or frame-size change; native keeps `PictureInPictureParams`
  current so Android 12+ auto-enters on leave and Android 8–11 enter from
  `onUserLeaveHint` (`PictureInPictureDecision.entryMode`). In PiP the
  page renders one full-bleed remote tile, no controls. When the last
  remote camera goes off, or the call ends, native hides the window with
  `moveTaskToBack(false)` and the call carries on behind the ongoing
  notification. The window's Hang up action reuses the notification's
  `CallActionReceiver` broadcast. iOS has no PiP: `pictureInPicture` is
  off there, so `setPictureInPicture` is never sent.
- **Adaptive call quality** (`CloudflareCallEngine`, `getStats()` every
  3s) classifies this device's own connection with separate enter/exit
  thresholds and streak counts, so one bad sample can't flap the tier
  (`CallQualityClassifier`: down after 2 consecutive bad samples, up
  after 4 consecutive clean ones):

  | Tier | Enter (loss or RTT) | Exit (loss and RTT) |
  |---|---|---|
  | degraded | >= 5% or >= 350ms | < 3% and < 250ms |
  | poor | >= 12% or >= 700ms | < 8% and < 500ms |

  Each tier writes explicit encoding limits (`videoEncodingFor`) to the
  local video sender's `RTCRtpParameters` via `applyVideoEncodingLimits`
  (a pure function setting `scaleResolutionDownBy`/`maxFramerate`/
  `maxBitrate`, tested without WebRTC) and `setParameters`, no
  renegotiation — applied at sender creation too, so the good tier's cap
  is the default from frame one, not just a ceiling reached after a drop:

  | Tier | Scale | fps | kbps |
  |---|---|---|---|
  | good | 1.0 | 30 (24 low-data) | 800 (500 low-data) |
  | degraded | 2.0 | 15 | 300 |
  | poor | 2.0 | 10 | 150 |

  What actually gates outgoing video quality is the *worse* of this
  device's own reading and the other participant's last-reported quality
  (`lowBandwidth` on `fociInfo`) — otherwise a struggling downlink on one
  end gains nothing from the other end sending more than it can absorb.
  Audio is never scaled. **Gotcha**: `RTCRtpEncoding.toMap()` omits null
  fields and Android only updates present keys, so every tier must write
  explicit `maxBitrate`/`maxFramerate` — a null never lifts a cap.
- **Bandwidth ceiling**: capture is capped at 480p30 regardless of
  setting; "Use less data for calls" (on by default) drops it to 360p24. Read
  once per call (not watched live) — switching mid-call would mean
  re-capturing the camera.
- **Video codec order is per platform** (`videoCodecOrder`). Android pins
  VP8, then H264, via `setCodecPreferences`: VP8 has a software fallback
  in this build, H264 does not. iOS sets none: flutter_webrtc's iOS side
  finds a transceiver by `mid`, which is empty before negotiation, so the
  call lands on the first transceiver (audio) and fails. WebRTC's iOS
  default already puts hardware H264 first. Every SFU receiver decodes
  both, so the asymmetry is harmless.
- **iOS mutes through the input mixer** (`callMuteByInputMixer`, set at
  `join`). Disabling the audio track mutes the audio device module; in
  flutter_webrtc's default voice-processing mode that mute outlives the
  call and every later recording in the app captures silence until
  relaunch. `inputMixer` mode is call-local and also skips iOS's mute
  sound. CallKit's own mute is system-wide and can linger the same way,
  so `CallAudio` clears it after the last call.
- **CallKit**, the why behind the iOS shape:

  | Decision | Why |
  |---|---|
  | The only iOS ring UI; `IncomingCallPage` only when CallKit is unavailable | No double ring UI, and a filtered ring must stay silent |
  | The system call follows `activeCallProvider`, not `CallPage` | Nothing renders while locked, so a lock-screen answer may never build the page |
  | flutter_webrtc's session management off; the AVAudioEngine ADM gated by `setEngineAvailability` from `didActivate` (armed by `CloudflareCallEngine.join`) | Audio must start in the session CallKit activates, and `useManualAudio` gates nothing on this ADM |
  | One `playAndRecord`/`voiceChat` session, speaker only by override | A mid-call mode change rebuilds the engine |
  | Native owns the starting route, and restores the last reported one after a media-services reset or a category change | A late `CallPage` build would undo a route picked on the CallKit screen |
  | Dart mutes, native mirrors with tagged actions, a refused unmute reverts Dart; `begin` hands over a mute made before the app took the call | CallKit's mute holds the uplink system-wide, so the two must never disagree |
  | Native ring backstop 55 s; a system end after 25 s of ringing counts as missed, earlier as a decline | CallKit ends a ring on its own near 60 s, and that end looks like a decline |
  | Recents off; the handle is the room's opaque token (`zuno` without one), never a name | Recents sync through iCloud, nothing handles a redial, and system stores keep what a call shows |
  | Ringtone off plays `silent_ring.caf` | CallKit otherwise plays the system ringtone |

- **Call waiting**: a second incoming call while already on one, or while
  another call rings (`SystemRing`), is auto-declined, never rung, with a
  "Missed call from X" SnackBar. The main isolate declines it from sync
  (`room_list_page.dart`; on iOS `RingCoordinator`, and a pushed ring that
  finds CallKit busy is a placeholder ended at once). A push handled in a
  headless isolate can't read `activeCallProvider`, so the notifier
  mirrors it into a process-wide `IsolateNameServer` marker
  (`active_call_marker.dart`) and the push handler stays silent while it is
  set, or while another unresolved call rings: a push never replaces a
  ringing call. The marker dies with the process, so a crash can't mute
  later rings; the notifier clears it on build because a mapping outlives a
  hot restart.
- **A ring ends when another of my devices answers or declines**
  (`ringElsewhereProvider`, both platforms): my membership on another
  device joining the call, or my decline from any device, ends the ring
  and resolves the call. A call already answered elsewhere never rings, is
  never declined as busy, and loses any ring the push isolate posted. Only
  an app that is syncing watches: nothing about an answer elsewhere pushes,
  so a ring posted headless learns of it only once the app syncs; the
  native 60 s stop ends it regardless.
- **TURN provider selection was built, then retired to one path.** A
  per-user `TurnProviderKind` (homeserver vs. Cloudflare) picker existed
  briefly; both branches are now moot — the app derives ICE entirely
  through the module, and which provider is actually behind it is a
  server-side fact that doesn't need a per-device choice. Deliberately
  *not* built as a `CallEngine`-style polymorphic interface — TURN is one
  fetch at call setup, not a multi-operation lifecycle.
- **LiveKit adapter designed for, not built.** The `CallEngine` interface
  already accounts for a second backend. The `matrix` SDK ships its own
  VoIP module (`GroupCallSession`, membership lifecycle, glare handling,
  to-device 1:1 signaling) with pluggable mesh/LiveKit backends — not used
  for the Cloudflare adapter since `CallBackend.fromJson` hard-codes only
  those two backend types. If a LiveKit adapter is built, building it
  directly on the SDK's own voip module may be less work than extending
  this app's custom signaling layer to a second backend.
- **The ring plays natively and process-wide, not as a channel sound**
  (`IncomingRing` in `zuno_call_style`): one looping `MediaPlayer`
  (`assets/sounds/ringtone.wav`, ringtone usage) and the vibrator, keyed by
  the ringing call id and never touched when an engine detaches. Dart passes
  the Ringtone and Vibrate-for-calls settings with `showIncomingCallStyle`.
  Why native: Dart-owned audio dies with its engine and never stops while
  the process is frozen. Why not the channel: a channel plays its
  sound/vibration once and can never change after first registration, so
  `calls_ringing` and `calls_ringing_group` are created with
  `playSound: false, enableVibration: false`. Every stop names the call and
  cancels the others:

  | Stop | Covers |
  |---|---|
  | `cancelIncomingCallStyle`, from every `cancelIncoming` | Live sync, the push handler, ring page dispose, cold-start accept |
  | The notification's delete intent | A swipe, and its own 60 s `setTimeoutAfter`; the system delivers it even while the app is frozen or in Doze |
  | The Answer intent | Silences at once when Answer launches the activity |
  | An `AlarmManager` window at 60 s | Backstop for a frozen process |
  | An in-process 60 s timer | A live process |

- **Ringback is a native `ToneGenerator` on `STREAM_VOICE_CALL`**
  (`AndroidRingbackTonePlayer` → `MainActivity.kt`), not a bundled asset —
  it needs to ride the call's own audio
  stream so it follows earpiece/speaker routing and in-call volume for
  free, without touching global audio state or requiring audio focus.
  Ringback keys off `CallSession.everHadRemote`/`remoteJoinedStream`
  (driven by `m.call.member`, the same membership source of truth used
  everywhere else) — not call `phase == active`, which for the caller
  only means "our own SFU join finished," unrelated to the other side
  answering.
- **The ring and ringback request no audio focus**: a ringback taking focus
  would get paused the moment the call's own audio session claims
  `AUDIOFOCUS_GAIN`, and Android denies a focus request from a
  non-foreground app outright (confirmed on Android 16). Routing and volume
  still follow the ringtone and voice-call usages; only the "duck other
  apps" behavior is given up.

## Gotchas & Constraints

- **Everything over live video is drawn on every video frame**, 24 to 30
  times a second with no raster cache, on a phone already encoding video.
  So: no `clipBehavior` on the control buttons (the ripple stays round
  through `InkWell.customBorder`), no `ClipRRect` on a square tile (the
  full-screen and picture-in-picture video), no blur, no `Opacity`, and
  `CallTimer` repaints inside its own `RepaintBoundary`. The engine
  de-duplicates participant updates, so the page rebuilds on events only.
- **`CallView`'s stack has fixed, keyed slots** (stage, notice, overlay,
  quality, confirm, controls), the notice slot always present. An unkeyed
  conditional sibling would remount everything after it when a notice
  appears, dropping a press already in progress on End call and
  restarting the tiles. `CallGrid` is one `Stack` of keyed cells for the
  same reason: a tile's state follows the person when people join or
  leave.
- **An ended call pops every route above its own before popping itself.**
  `_finish` used to `pop()` the top route, so a sheet or verification page
  left open over the call was closed instead, stranding an ended
  `canPop: false` call screen.
- **`session.engine` is null until the call connects.** Anything the build
  reads from it needs the `connecting` guard (`quality` does). Callbacks
  are fine; the buttons that use them are disabled while connecting.
- **End call never shows a tooltip on press-and-hold**
  (`TooltipTriggerMode.manual`): a tooltip's long-press recognizer would
  swallow the release and the call would not end. Each control is one
  semantics node (name, button role, enabled state).
- **`_reconcileRenderers` re-assigns `srcObject` on every participant
  change**, one platform call per participant. Left as is on purpose: it
  is event-driven, and re-assigning may be what rebinds a replaced track.
- **`hangUp()` must be idempotent — memoized, not phase-guarded.** Four
  call sites reach `hangUp()` and three fire un-awaited off a stream or
  timer (hang-up button, decline event, ring timeout, last-remote-left).
  Overlapping hangups are the everyday case, not an edge case. A bare
  `if (_phase == ended) return` guard is insufficient because phase is only
  set at the *end* of the teardown (six awaits later) — a second caller
  arrives well inside that window. Fix pattern: `hangUp() => _hangUp ??=
  _hangUpOnce()`, so every racing caller awaits the same future and
  teardown (membership clear, `engine.leave()`, `dispose()`, summary send)
  runs exactly once regardless of caller count. The first caller's flags
  stick: `byUser` (the hang-up button) and `summarized` (the call already
  has a summary, so none is sent).
- **Engine teardown must survive being told twice, and must not block on
  in-flight negotiation.** `leave()` must no-op on a second call;
  `dispose()` must chain onto `leave()` rather than run concurrently with
  it (closing stream controllers while `leave()` is still suspended makes
  its own next statement throw against its own closed controller).
  Teardown deliberately does *not* wait on the negotiation lock before
  closing/disposing the peer connection — blocking hangup on an
  in-flight network round trip is the worse trade. Consequence: any
  negotiation step resumed after teardown must re-check liveness (e.g.
  `!_left && identical(_pc, pc)`) after *every* await, not just once at
  entry, since the answer can change while suspended. Un-awaited
  post-teardown call sites must go through a best-effort wrapper — a
  native call already in flight, or a module 502, is a live failure mode.
- **`_setStatus`/notify-style methods must check `isClosed`** — native
  callbacks (connection-state changes, remote-track events) can still
  land after `dispose()` and are not something Dart code can order
  against.
- **A negotiation round must serialize against every other negotiation on
  the same `RTCPeerConnection`**, not just against itself — a third+
  participant joining an in-progress group call is exactly the scenario
  where two different remotes' negotiation rounds race concurrently
  (Cloudflare serializes negotiation state server-side regardless, so an
  app-side race always loses one side). This is what `NegotiationLock`
  exists to prevent; without it, symptoms range from a rejected HTTP call
  to a real native libwebrtc abort from repeated transceiver add/remove.
- **A transceiver's cached `.mid` never updates after construction** in
  `flutter_webrtc` — always re-fetch via `pc.getTransceivers()` after
  negotiation and match by stable key (`sender.senderId` for publish,
  mid ownership for pull), never by position or a freshly-generated
  `transceiverId` (which churns per call for as long as mid is unset).
- **Never `stop()` a pulled transceiver locally.** Cloudflare frees a
  closed track's mid without renegotiating and hands the same mid to the
  next pull; a locally stopped transceiver on that mid has no receiver,
  so the cryptor wrap throws, and if that aborted the answer the
  connection would sit in `have-remote-offer` for the rest of the call.
  Closing only tells the SFU; the pull path wraps receivers best-effort,
  always answers, and rolls back an offer it could not answer.
- **A pulled/pre-existing transceiver's `onTrack` only fires once** — if a
  transceiver already existed before this device's own pull-mapping was
  registered (e.g. a participant already active when this device joined),
  the "diff before/after" approach for detecting new transceivers misses
  it permanently. Requires explicitly adopting whatever's already on
  `receiver.track` rather than waiting for a callback that already fired.
- **Any activity destroy mid-call — the PiP window's X, swiping the
  task away, a system kill — would take the Flutter engine, and the
  call, with it.** `MainActivity.onDestroy` sends `hangUpCall` to Dart
  while a call is active (`CallHangUpDecision.onHostDestroyed`; "active"
  is tracked from the foreground-service start/stop channel calls), as
  does `onPictureInPictureModeChanged(false)` while only `CREATED` when
  the app did not hide the window itself (`PictureInPictureDecision.onLeft`,
  the user closing it). `shouldDestroyEngineWithHost` then defers
  `engine.destroy()` by 5 s so membership clear, `leave()` and the summary
  get out first, and stops `CallForegroundService` natively when that
  grace ends so its notification can't outlive the engine. Keeping the
  call alive across a destroy would need engine caching across activity
  restarts, which is not built.
- **"Everyone left" needs two consecutive empty membership passes, the
  second on a 2 s timer** (`remoteLeftConfirmDelay`). A remote's republish
  once read back as empty for a single sync tick and hung up a live call,
  so one pass is never acted on. The confirming pass used to be the next
  sync response, which while backgrounded is unrelated traffic or the
  30 s long-poll timeout — a remote leaving while you're still present
  sends no summary event — so the timer re-runs the reconcile against
  local state instead. A remote reappearing before it fires cancels it.
- **Foreground service must start unconditionally, first thing, the
  moment `CallPage` exists** — not gated on reaching `active` phase.
  Android only allows starting a new foreground service from a handful of
  exempted app states ("recently interacted with" chief among them); a
  multi-step join path (accepting into an already-active group call) can
  drift outside that exemption window if the service start waits on the
  full connect sequence.
- **Permission grant must be awaited before the foreground-service start
  that requires it**, even though the service start must also be
  unconditional/first — `ensurePermissions()` is memoized so both the
  explicit pre-check and the connect sequence's own internal request
  share one real platform-channel call rather than racing or duplicating
  it.
- **The ring's `AlarmManager` backstop fires 60–105 s after the ring**:
  Android 12+ stretches short windows. The delete intent is the precise
  60 s stop, so only a ring whose notification is blocked can sound that
  long.
- **`AssetManager.openFd` refuses a compressed asset**, so `IncomingRing`
  falls back to a copy of the ringtone in `cacheDir` (`zuno_ringtone`).
- **The ring cancels the vibrator only if it started a vibration itself**,
  so stopping a silent ring never cuts a message buzz.
- **`room.states` (the SDK's in-memory state cache) is only kept live for
  event types in `client.importantStateEvents`.** `m.call.member` is
  non-standard and must be added explicitly at client construction
  (`createMatrixClient()`) — otherwise a membership update persists to
  the database but is silently dropped from memory on a `Room` this app
  never calls `postLoad()` on, and one side of a call never sees the
  other join.
- **Only the app's `initialize()` claims the live routes.** `main.dart`
  calls it with the default; every other caller (the presenters,
  `showMessage`, the headless entries through `prepareHeadlessPush`) passes
  `claimDeclinePort: false`. A new entry point must too, or it takes the
  routes away from the app.
- **Push-delivered headless call handling must not serialize the "ring
  down" push behind the "ring up" push's own long-lived hold.** A single
  queue serializing all headless pushes on one client/database, combined
  with a 45s blocking wait *inside* that same queued unit (to keep a
  client alive for a Decline tap), starves every other push — including
  the hangup summary that's supposed to cancel the ring — for the whole
  ring duration. FCM runs the hold from `onRinging`, beside the ack;
  UnifiedPush awaits it in `onPushHandled`, after the client work.
- **`CallStyle.forOngoingCall`'s second argument is the hang-up intent,
  not a content intent.** Handing it the app-launch PendingIntent
  compiles, renders a normal-looking Hang up button, and silently does
  nothing but re-open an already-open app. `forIncomingCall(person,
  declineIntent, answerIntent)` has the same trap: the slots are
  positional and every one takes a `PendingIntent`, so a mis-wire is
  invisible until a real tap on a real device.
- **Sending resources (`/sessions/new`, `/tracks/new`) must not be
  retried past the transport-failure boundary** — retrying a request that
  may have already landed server-side risks a duplicate session/track.
  Only a `SocketException` (never reached the module) and a 429 (the
  module refuses before calling Cloudflare) are safe to retry on these
  paths.
- **A call summary must be sent unconditionally on every end path** — it
  is the only signal guaranteed to reach the other side regardless of
  which end reason applies (declined, missed, hangup, caller-cancel
  before answer), and both the caller's decline-listener and the callee's
  ring-page dismissal-listener depend on it arriving rather than on a
  more specific signal.
- **Server-side push-rule content conditions cannot fire on call
  signaling in encrypted rooms** — the server only ever sees
  `m.room.encrypted` ciphertext for `call_invite`/`call_decline`/
  `call_summary`. Only the cleartext `m.relates_to` is visible, which is why
  silencing goes through the `m.reference` relation, and any unread/badge
  correction keyed on call semantics happens client-side against decrypted
  content.
- **Well-known homeserver lookups (`client.getWellknown()`) already cache
  for 3 days** at the SDK level — worth checking before adding another
  cache layer on top for module URL derivation.
- **`endIncomingCall` ignores an answered call.** The router cancels the
  ring on every accept, and by then CallKit's call is the ongoing one.
- **A CallKit callee can join a call that is already over** (the caller
  gave up while the answer was on its way). The binding hangs up
  `summarized: true` when the call's summary lands before anyone joined,
  so no second missed summary goes out, and a callee still alone 15 s
  after going live hangs up (`emptyCallTimeout`).
- **A lock-screen answer cannot show a permission prompt.** With the
  microphone not yet granted, `CallSession` waits 3 s for the app to reach
  the foreground, else the call ends with "Allow Zuno to use the
  microphone, then call back."
- **Native watchdogs end a stuck call as failed** (`callFailed`, "Call did
  not connect"): an answer the app never adopts within 30 s (45 s for a
  pushed ring), or a session CallKit never activates within 10 s. Every end
  holds a 15 s background task so `leave()` and the summary get out.
- **Two calls overlap briefly on End & Accept.** `hangUpCall` names the
  call CallKit ended (Android's Hang up names none): the router hangs up
  only that call, marks any other id resolved, and holds the next accept
  until it has ended (5 s at most). So `ActiveCallNotifier.clear(session)`
  is identity-checked, and an ended `CallPage` under the new one skips its
  teardown side effects and removes its own route instead of popping.
- **`CallsChannelPlugin` registers only on `EngineHost`'s engine.**
  `CallKitCenter` is process-wide: another engine registering it would
  take the channel over, and its `resetSystemCalls` would end the calls
  the main Dart owns. Engine detach ends those calls and closes WebRTC
  media.
- **iOS detaches a video renderer before disposing it**
  (`videoRendererNeedsDetach`): `CallPage` clears its `srcObject`, waits
  500 ms, then disposes. flutter_webrtc's iOS renderer queues main-thread
  frame blocks that dereference a nil `strongSelf`, so disposing one with
  frames in flight crashes the app, and a crashed app never clears its
  `m.call.member`.
- **The `zuno_push` module's `sygnal_notify_url` needs a hostname without
  `_`.** Synapse's HTTP client IDNA-encodes the host and fails before
  connecting: the module logs "Sygnal answered nothing" while curl to the
  same URL works, and no ring goes out. Message pushes use the public
  notify path, so they can keep working (`notifications.md`).

## Extension Guidance

- A second media backend (e.g. LiveKit) belongs behind `CallEngine`,
  implemented as a sibling to `CloudflareCallEngine` — the call UI and
  `CallSession` signaling layer should need no changes. The interface's
  only local-state signal is `localStateChangedStream` (any local
  mute/camera/quality-tier change fires it, triggering an immediate
  membership republish); it carries no screen-share or voice-downgrade
  methods, so a new backend need not implement either. Evaluate building
  it on the `matrix` SDK's own voip module (LiveKit is one of its two
  native backends) rather than extending this app's custom MatrixRTC-lite
  signaling layer to a second backend.
- Any new mid-call membership fact (mute, video-enabled, low-bandwidth,
  and any future field) should ride `fociInfo` on the existing
  `m.call.member` republish — that's the one channel both sides already
  watch and reconcile off, and piggybacking triggers the same
  immediate-republish-on-change pattern mute/camera already use instead
  of waiting on the 50s periodic refresh.
- New signaling needs (beyond invite/decline/summary) should default to
  another custom `im.zuno.*` msgtype on `m.room.message`, matching the
  existing voice-message precedent, unless there's a concrete reason to
  need a bespoke event type — the msgtype route gets pagination/filtering
  for free and is filterable out of the rendered timeline the same way.
- Any change to hangup/teardown ordering must preserve: idempotency
  (memoized, not phase-guarded), no blocking on in-flight negotiation, and
  `isLiveConnection`-style re-checks after every await in code that can
  resume post-teardown. Add coverage in the engine harness:
  `CloudflareCallEngine` takes a `WebRtcBackend` (defaults to
  flutter_webrtc's globals), faked by `test/helpers/fake_webrtc.dart`
  against a scripted SFU (`cloudflare_engine_harness.dart`, under
  `fakeAsync`). Only real media and a live SFU stay untested.
- Server-side changes (rate limiting, concurrent-call caps, abuse
  controls) belong in the `zuno_calls` module, not the client — the client
  only ever holds a Matrix access token and expects the module to enforce
  everything downstream of that. See Dependencies below for the current
  state of that enforcement.
- `CallPage` is one page across the whole call lifecycle (the portrait
  stage stands in until someone is there, not a separate screen) — a new
  phase or state extends `CallStatus` and `CallView`, never a
  phase-specific full-screen swap.
- A change to how a call looks goes in `CallView` and its pieces, which
  take plain values and are tested without a session
  (`call_view_test.dart`, with `expectSurvivesLayoutMatrix`).
  `CallPage`'s side effects are tested through `call_page_harness.dart`
  (a `FakeCallSession` the test drives, plus recorders for every platform
  channel). Keep the real-session case in `call_page_test.dart` passing:
  it catches a build that touches `session.engine` before the call
  connects.
- The CallKit path is tested on Linux as iOS: `installFakeCallsChannel` /
  `sendFromNative` (`test/helpers/fake_calls_channel.dart`) record and
  play `zuno/calls`; `FakeCallSession` lives in `test/helpers/`.
  `flutter_test_config.dart` resets `SystemRing`, the presenter's ring
  memory and every `KeyedSerialLock` after each test. Native decisions have
  XCTests (`ios/RunnerTests/`: `RingDecisionTests`, `PushRingHandlerTests`,
  `CallKitCenterPushTests` among them) and JUnit tests
  (`IncomingRingDecisionsTest`, over `RingDecisions`). The VoIP blob,
  CallKit UUID and opaque-id vectors (`test/fixtures/push/`) run in Dart and
  Swift, and the `zuno_push` module must pass the same files: change them
  on both sides together. On a device, `tool/push_test/apns_send.swift`
  sends a sealed VoIP push or an alert straight to APNs, with the values
  from Push target's development card (reached from Diagnostics).

## Dependencies / Integration

- **Matrix SDK**: `m.call.member` state events (custom, added to
  `importantStateEvents`), `client.sendToDeviceEncrypted` (Olm, call E2EE
  key relay), `client.onTimelineEvent`/`onSync` (membership reconcile,
  live-call ringing), `room.canChangeStateEvent` (power-level gate reused
  by `canPublishCallMemberState`).
- **Notifications**: `NotificationDeliveryProvider` (FCM/UnifiedPush/
  background-service) is what makes ringing work while backgrounded or
  killed on Android, the `zuno_push` VoIP push on iOS; the extension and
  the read model it shares with the ring are in `notifications.md`. The
  platform seams own the ring/ongoing-call notification lifecycle (on
  Android, `zuno/call_style` and `CallForegroundService.kt`; on iOS,
  CallKit). Calls share the raw-prefs sound settings with message
  notifications, readable from any engine, with distinct toggles (Ringtone
  / Vibrate for calls, vs. Message tone / Vibrate for messages); the ring
  plays natively in `IncomingRing`. Declines share the live routes and the
  action engine with the message actions.
- **Room roles & permissions**: `canPublishCallMemberState` mirrors the
  same power-level model documented for room roles generally — calling
  requires the same state-event send permission the homeserver itself
  enforces on `m.call.member`.
- **`zuno_push` Synapse module (external, its own repo)**: rings closed iOS
  devices (iOS ring path), answers the extension's `ring/status` and holds
  each device's VoIP token and key. The app's client is
  `zuno_push_api.dart` (`notifications.md`); `zuno_calls` is untouched by
  it.
- **`zuno_calls` Synapse module (external, its own repo)**:
  `calls_module.dart` is a client against a module loaded into the
  homeserver, not part of this app. It proxies Cloudflare Calls (SFU)
  signaling and Cloudflare TURN credential minting under
  `/_synapse/client/zuno/calls/cloudflare/`, authenticated by Synapse's own
  access-token check, rate-limited per (user, device) with a token bucket
  (429 + `retry_after_ms`, before Cloudflare is called), and answering 502
  when Cloudflare is unreachable. **Known gap**: it has no
  per-account-age minute limits, concurrent-call caps or circuit breaker —
  a free-tier account plus a per-minute-billed SFU is a direct
  billing-abuse vector with no other victim, and the module is the only
  place that can be enforced.
