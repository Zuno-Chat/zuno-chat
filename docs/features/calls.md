# Calls

## Overview

Voice/video calling, 1:1 and group, WhatsApp-like in UX. All calls —
including 1:1 — are routed through a configured SFU; there is no P2P mode,
by design. Signaling is a custom, simplified layer loosely modeled on
MatrixRTC (MSC3401), not a conformant implementation. Media runs through a
pluggable `CallEngine` abstraction, currently backed by Cloudflare Calls,
proxied through a homeserver-side gateway so the app never holds SFU
credentials.

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
- **`calls_gateway.dart`** — a homeserver-side HTTP proxy in front of the
  SFU/TURN provider. The app authenticates to it with the user's own Matrix
  access token as a bearer; the gateway validates that token and holds the
  actual Cloudflare credentials. Only signaling (SDP/track metadata, small
  JSON round trips at call setup) is proxied — RTP media flows directly
  between device and SFU, so the gateway is not in the media path and only
  affects call-setup latency.

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
- Ringtone/ringback/vibration: `notification_sound_player.dart` +
  `CallNotificationService` (see Communication below).
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

**End reasons** (`CallSession.endReason`) distinguish declined / missed /
declinedByThem / failed / normal hangup — `failed` carries a user-facing
`failedMessage` (e.g. permission-denied) surfaced via snackbar.

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
  enforced client-side only — the gateway has no notion of which call a
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

**Cloudflare Calls dialect via the gateway.** `calls_gateway.dart` derives
`https://{homeserver-host}/calls` (SFU) and
`https://{homeserver-host}/turn/credentials` (TURN) from `client.homeserver`
— the `.well-known`-*resolved* host, not the address typed at login (they
differ when a homeserver delegates); a homeserver served under a path
prefix has that prefix dropped, since the gateway is rooted at the host.
`CloudflareApiClient` keeps Cloudflare's own paths/JSON verbatim; the
gateway is a signaling proxy with `/apps/{appId}` filled in server-side, so
engine-side negotiation logic is unchanged by the proxy — only base URL and
auth changed. Auth is an enrolled per-device gateway token
(`CallsGatewayCredentials`), not the Matrix access token: the app enrolls
once per device at `POST /calls/enroll`, stores the returned token in
secure storage, and sends it as `Authorization: Bearer <token>` on every
gateway request. Tokens last 24 hours from issue, fixed, no sliding; the
app re-enrolls when its stored token is within a minute of that expiry,
and once on a 401. Secure-storage failures never fail a call: an
unreadable stored token just enrolls again, and a failed write still
returns the minted token. See
`docs/decisions/calls-gateway-enrollment.md` for the full contract and
rationale.

**Negotiation roles differ by direction** — publish (local
mic/camera → offer → `pushLocalTracks` → answer) is standard
offerer-us/answerer-Cloudflare WebRTC; **pull** (subscribing to another
participant's tracks) is the reverse: Cloudflare's `tracks/new` response
for a pull carries an *offer*, so the correct sequence is
`setRemoteDescription(Cloudflare's offer)` → `createAnswer()` →
`setLocalDescription` → PUT the answer to `/renegotiate`.

**ICE gathering is not trickle** on Cloudflare's REST signaling — there's
no endpoint to send candidates as they arrive, so an offer must already
carry them. Negotiation therefore waits for gathering to reach an idle
cutoff (genuinely complete, or ~500ms with no new candidate) before
sending, with a 3s hard ceiling as backstop for a stalled network.

**Retries**: `lib/core/errors/backoff.dart` (`backoffDelay`, full-jitter
exponential) + `retry_backoff.dart` (`retryWithBackoff`), wired into the
calls-gateway HTTP clients only — nothing else in the app retries
automatically.
- `CloudflareApiClient._send` retries *only* `SocketException` (request
  never reached the gateway). A non-2xx status or `http.ClientException`
  is **not** retried — `/sessions/new` and `/tracks/new` create resources,
  so retrying a request that may have already landed risks a duplicate
  session/track server-side. Kept short (3 attempts, sub-2s ceiling)
  since these calls sit inside live SDP negotiation.
- `fetchCloudflareIceServers` (TURN) retries more liberally — any network
  failure or 5xx, not just pre-response — because minting a TURN
  credential is idempotent. A 4xx is not retried.

**TURN**: `resolveIceServers` (`ice_servers.dart`) fetches credentials
through the gateway; a failed mint yields an empty ICE list rather than
failing the call — TURN only matters for the subset of networks that
can't manage a direct/STUN-assisted path. (A selectable homeserver-vs-Cloudflare
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
ringing while the process is alive; a persistent foreground service
(default notification delivery mode) keeps the process from being
suspended for the common backgrounded case. Push (FCM/UnifiedPush)
delivers to a headless engine for the genuinely-killed-process case. A
ring notification carries its own Accept/Decline actions and a
full-screen intent; `CallForegroundService.kt` backs the persistent
in-call notification once active (Android requires a real foreground
service for background mic/camera capture).

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
- **`/sync` stays alive while a call is active, even backgrounded.**
  Remote departure, declines and key delivery all arrive only through
  sync. The app-foundation "backgrounding pauses `/sync`" rule takes an
  `inCall` flag and stands down for the call's duration (the foreground
  service keeps the process alive); `_AuthGate` pauses sync when the
  active call clears while still backgrounded.
- **Voice calls turn the screen off at the ear via Android's
  `PROXIMITY_SCREEN_OFF_WAKE_LOCK`** (`MainActivity.setProximityScreenOff`
  over `zuno/calls`), the system dialer's mechanism — no sensor plumbing
  in Dart. `call_proximity.dart` decides: wanted only for a voice call
  with the speaker off and the call not finished (ringing counts).
  `CallPage` syncs it on init, speaker toggle, voice→video and finish;
  native also releases it on engine cleanup and activity destroy.
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
  `CallActionReceiver` broadcast.
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
- **Video codec order is pinned VP8, then H264** via
  `setCodecPreferences` — VP8 has a software fallback in this build,
  H264 does not.
- **Call waiting**: a second incoming call while already on one is
  auto-declined, never rung.
- **TURN provider selection was built, then retired to one path.** A
  per-user `TurnProviderKind` (homeserver vs. Cloudflare) picker existed
  briefly; both branches are now moot — the app derives ICE entirely
  through the gateway, and which provider is actually behind it is a
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
- **Ringtone/ringback/vibration are app-played, not notification-channel
  sounds.** An Android notification channel plays its sound/vibration
  pattern once and can never change after first registration — incompatible
  with a ring that must continue until answered and toggles that must take
  effect immediately. `calls_ringing` (and its group-call sibling,
  `calls_ringing_group` — see the notifications feature doc) is created
  with `playSound: false, enableVibration: false`; everything
  audible/haptic comes from `notification_sound_player.dart`. Ring sound
  and ring notification share one start/stop lifecycle, keyed to
  `CallNotificationService.showIncomingCall`/`cancelIncomingCall` (the
  choke points every path — live sync, push handler, ring page dispose,
  cold-start accept — goes through), with a 60s backstop timer past the
  45s ring timeout.
- **Ringback is a native `ToneGenerator` on `STREAM_VOICE_CALL`**
  (`MainActivity.kt`), not a bundled asset played through `audioplayers`
  like every other app sound — it needs to ride the call's own audio
  stream so it follows earpiece/speaker routing and in-call volume for
  free, without touching global audio state or requiring audio focus.
  Ringback keys off `CallSession.everHadRemote`/`remoteJoinedStream`
  (driven by `m.call.member`, the same membership source of truth used
  everywhere else) — not call `phase == active`, which for the caller
  only means "our own SFU join finished," unrelated to the other side
  answering.
- **All app sounds request no audio focus**
  (`AndroidAudioFocus.none`) — both because a ringback taking focus would
  otherwise get paused the moment the call's own audio session claims
  `AUDIOFOCUS_GAIN`, and because Android denies a focus request from a
  non-foreground app outright (confirmed on Android 16) with no
  `audioplayers` fallback for a denied request — it just never plays.
  Routing/volume still goes through the ring/notification/voice-call
  usage types; only the "duck other apps" behavior is given up.

## Gotchas & Constraints

- **Everything over live video is drawn on every video frame**, 24 to 30
  times a second with no raster cache, on a phone already encoding video.
  So: no `clipBehavior` on the control buttons (the ripple stays round
  through `InkWell.customBorder`), no `ClipRRect` on a square tile (the
  full-screen and picture-in-picture video), no blur, no `Opacity`, and
  `CallTimer` repaints inside its own `RepaintBoundary`. The engine
  de-duplicates participant updates, so the page rebuilds on events only.
- **`CallView`'s stack has fixed, keyed slots** (stage, notice, overlay,
  quality, controls), the notice slot always present. An unkeyed
  conditional sibling would remount everything after it when a notice
  appears, dropping a press already in progress on End call and
  restarting the tiles. `CallGrid` is one `Stack` of keyed cells for the
  same reason: a tile's state follows the person when people join or
  leave.
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
  runs exactly once regardless of caller count.
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
  native call already in flight, or a gateway 500, is a live failure mode.
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
- **Vibration is process-wide state; a ring sound handle is per-isolate.**
  A push-delivered ring can be started in a headless isolate and stopped
  in the main one after cold-start. Cancel the vibrator unconditionally
  from any isolate (safe — the vibrator is a system service, and
  cancelling a non-running vibration costs nothing). Audio must be routed
  isolate-to-isolate explicitly (an `IsolateNameServer` stop-port,
  local-only on receipt so a forwarded stop can't bounce back into a loop).
- **`room.states` (the SDK's in-memory state cache) is only kept live for
  event types in `client.importantStateEvents`.** `m.call.member` is
  non-standard and must be added explicitly at client construction
  (`createMatrixClient()`) — otherwise a membership update persists to
  the database but is silently dropped from memory on a `Room` this app
  never calls `postLoad()` on, and one side of a call never sees the
  other join.
- **Push-delivered headless call handling must not serialize the "ring
  down" push behind the "ring up" push's own long-lived hold.** A single
  queue serializing all headless pushes on one client/database, combined
  with a 45s blocking wait *inside* that same queued unit (to keep a
  client alive for a Decline tap), starves every other push — including
  the hangup summary that's supposed to cancel the ring — for the whole
  ring duration.
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
  Only a `SocketException` (never reached the gateway) is safe to retry
  on these paths.
- **A call summary must be sent unconditionally on every end path** — it
  is the only signal guaranteed to reach the other side regardless of
  which end reason applies (declined, missed, hangup, caller-cancel
  before answer), and both the caller's decline-listener and the callee's
  ring-page dismissal-listener depend on it arriving rather than on a
  more specific signal.
- **Server-side push-rule content conditions cannot fire on call
  signaling in encrypted rooms** — rooms are encrypted by default, so the
  server only ever sees `m.room.encrypted` ciphertext for
  `call_invite`/`call_decline`/`call_summary`; any unread/badge correction
  keyed on call semantics has to happen client-side against decrypted
  content, not via a server-side push rule.
- **Well-known homeserver lookups (`client.getWellknown()`) already cache
  for 3 days** at the SDK level — worth checking before adding another
  cache layer on top for gateway host derivation.

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
  resume post-teardown. Add coverage via the teardown-only test seam
  (`cloudflare_call_engine_teardown_test.dart`) — an engine that never
  joined has no native connection underneath, so pure teardown logic is
  actually testable, unlike the rest of the engine.
- Gateway-side changes (rate limiting, concurrent-call caps, abuse
  controls) belong in the gateway service itself, not the client — the
  client only ever holds a Matrix access token and expects the gateway to
  enforce everything downstream of that. See Dependencies below for the
  current state of that enforcement.
- `CallPage` is one page across the whole call lifecycle (the portrait
  stage stands in until someone is there, not a separate screen) — a new
  phase or state extends `CallStatus` and `CallView`, never a
  phase-specific full-screen swap.
- A change to how a call looks goes in `CallView` and its pieces, which
  take plain values and are tested without a session
  (`call_view_test.dart`, with `expectSurvivesLayoutMatrix`).
  `call_page_test.dart` pumps the real page with five stubbed channels;
  keep it passing, it is what catches a build that touches
  `session.engine` before the call connects.

## Dependencies / Integration

- **Matrix SDK**: `m.call.member` state events (custom, added to
  `importantStateEvents`), `client.sendToDeviceEncrypted` (Olm, call E2EE
  key relay), `client.onTimelineEvent`/`onSync` (membership reconcile,
  live-call ringing), `room.canChangeStateEvent` (power-level gate reused
  by `canPublishCallMemberState`).
- **Notifications**: `NotificationDeliveryProvider` (FCM/UnifiedPush/
  background-service) is what makes ringing work while backgrounded or
  killed; `CallNotificationService` and `CallForegroundService.kt` own the
  ring/ongoing-call notification lifecycle. Calls share the same
  best-effort, cross-isolate sound/vibration infra as message
  notifications (`notification_sound_player.dart`) but with distinct
  settings toggles (Ringtone / Vibrate for calls, vs. Message tone /
  Vibrate for messages).
- **Room roles & permissions**: `canPublishCallMemberState` mirrors the
  same power-level model documented for room roles generally — calling
  requires the same state-event send permission the homeserver itself
  enforces on `m.call.member`.
- **Calls gateway (external, homeserver-side)**: `calls_gateway.dart` is
  a client against a service that is a separate deployable, not part of
  this app. It proxies Cloudflare Calls (SFU) and Cloudflare TURN
  credential minting, authenticated by a gateway-issued per-device token
  obtained once with the Matrix access token. **Known gap**: the
  gateway needs per-user/per-account-age minute limits, concurrent-call
  caps, and a circuit breaker — a free-tier account plus a per-minute-billed
  SFU is a direct billing-abuse vector with no other victim, and the
  gateway is the only place that can be enforced. Needs verification
  against the gateway's actual current deployment/implementation, which
  lives outside this repo.
