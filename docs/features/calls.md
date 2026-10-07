# Calls

Voice and video calls, one-to-one and group (6 people at most), always
routed through Cloudflare's SFU behind the `zuno_calls` Synapse module.
There is no peer-to-peer mode, by design. Signaling is a custom layer
loosely modeled on MatrixRTC (MSC3401), not a conformant implementation.
Media is encrypted per frame with a random key for each call. Android rings
with a native `CallStyle` notification and keeps the call in a foreground
service. iOS rings through CallKit: from sync while Zuno runs, and from a
server-sent VoIP push while it is closed.

## Architecture

```mermaid
flowchart LR
  UI["CallPage → CallView"] --> S[CallSession]
  S -->|"m.call.member state, im.zuno.call_* messages"| HS[(Homeserver)]
  S -->|"call key, Olm to-device"| HS
  S --> E[CloudflareCallEngine]
  E -->|"SDP and track JSON, Matrix bearer"| M["zuno_calls module (in Synapse)"]
  M -->|"app id and credentials"| SFU[Cloudflare SFU]
  E <-->|"media, encrypted per frame"| SFU
```

| Part | Where | Role |
|---|---|---|
| `CallSession` | `lib/core/calls/matrixrtc/` | Matrix-side signaling and the call lifecycle: invite, decline, ring timeout, `m.call.member` publish and reconcile, the call key, hang-up and the summary |
| `CallEngine` → `CloudflareCallEngine` | `lib/core/calls/cloudflare/` | Media: one peer connection and one Cloudflare session per call, with every participant's tracks muxed onto it |
| `calls_module.dart` | same | Speaks Cloudflare's own API to the module, which adds the app id and credentials server-side. Only signaling goes through it; media flows straight between the device and the SFU |
| `CallPage` → `CallView` | `lib/features/calls/presentation/` | `CallPage` owns the session, the renderers and every side effect. `CallView` only lays out plain values |
| Ring routing | `lib/core/calls/notifications/`; iOS `RingCoordinator` | Presenting, cancelling, answering and declining rings |

**Platform seams** (`lib/core/calls/platform/`). Whatever the OS shows or
plays for a call goes through one of six interfaces, each built by a
`*For(capabilities)` factory that checks `callKit` first
(`app-foundation.md`).

| Seam | Android | iOS |
|---|---|---|
| `IncomingCallPresenter` | `CallStyle` notification with a native ring | CallKit |
| `OngoingCallPresenter` | `CallForegroundService` | No-op: CallKit shows the call |
| `RingbackTonePlayer` | `ToneGenerator` on the voice-call stream | A native synthesized tone |
| `SystemCall` | No-op | The CallKit call |
| `CallAudioOutput` | flutter_webrtc's audio routing | Native routes |
| `PushRingBridge` | No-op | Binds pushed rings to their calls |

### Call lifecycle

```mermaid
stateDiagram-v2
  [*] --> ringing: forIncoming
  [*] --> connecting: startOutgoing
  ringing --> connecting: accept()
  ringing --> ended: declined or hung up
  connecting --> active: joined, membership published
  connecting --> ended: failed or hung up
  active --> ended: hangUp()
```

- **Both factories return at once.** Connecting (permissions, the engine,
  the join and the first membership publish) runs in the background, so
  the call screen renders before any of it finishes.
- **A call ends** as hung up, declined by either side, missed (the
  caller's ring timed out with nobody joined) or failed. A failure carries
  a user-facing message.
- **"Prevent accidental calls"** (on by default, Settings → Chats & calls)
  asks for confirmation before a call starts.

### Signaling

- **`m.call.member` state is the only roster**: one entry per device in the
  call, never a client-local list. Each entry's `fociInfo` carries the
  Cloudflare session, the published tracks and media flags such as
  `videoEnabled`, `encrypted` and `lowBandwidth`. The room's "call in
  progress" banner reads the same state, so a missed ring or a closed app
  still finds the call.
- **Membership is republished periodically and on every change.** User
  toggles are coalesced, because state events are permanent room history.
- **Invite, decline and summary are `im.zuno.call_*` msgtypes** on
  `m.room.message`, so they ride the existing timeline plumbing. Only the
  summary renders.
- **Every end path sends a summary.** It is the one signal both sides can
  rely on: the callee learns of an early cancel from it, the caller of a
  late decline.
- **Declines and answered summaries carry an `m.reference`**, which stays
  cleartext in encrypted rooms, so a push rule keeps them off the push path
  (`notifications.md`). Missed and declined summaries still push, because
  they stop the ring on the callee's other devices.

**Group calls** break assumptions a one-to-one call could get away with:

- Leaving is not ending: whoever is last out posts the summary.
- Any device holding the call key relays it to a newcomer, not only the
  caller.
- The 6-person cap is enforced only on the client, since the module cannot
  tell which call a session belongs to. When simultaneous joins overshoot,
  each device ranks itself by join time and the extras hang up, with no
  coordination needed.

### Media

A publish and a pull run in opposite directions:

```mermaid
sequenceDiagram
  participant D as Device
  participant C as Cloudflare, via zuno_calls
  Note over D,C: Publish our tracks
  D->>C: sessions/new, then tracks/new with our offer
  C-->>D: answer
  Note over D,C: Pull a remote's tracks
  D->>C: tracks/new naming their session and tracks
  C-->>D: offer
  D->>C: renegotiate with our answer
```

| Rule | Why |
|---|---|
| ICE is gathered whole before an offer goes out | Cloudflare's REST signaling takes candidates only inside the offer, so there is no trickle ICE |
| A lost connection rejoins with a new session and peer connection, a few times, before the call ends as "Connection lost" | Cloudflare sessions cannot ICE-restart |
| TURN credentials are minted through the module at join, and a failed mint means no TURN, not a failed call | Only some networks need TURN |
| A black placeholder stands in whenever the camera is not sending, and a track is advertised only once it has sent bytes | Cloudflare drops a published track that receives no packets for 30 s, and advertising earlier lets someone pull a track the SFU does not have yet |
| Opus goes out without DTX | A muted microphone with DTX sends nothing, so the 30 s rule would drop the audio track |
| Every track swap is `replaceTrack`, never a mid-call re-offer | A re-offer recreates the receive streams, and Android's flutter_webrtc then renders nothing (flutter-webrtc#2124) |
| Android pins VP8, then H264. iOS sets no codec order and gets hardware H264 | Only VP8 has a software fallback on Android, and every receiver decodes both |

**The placeholder** is a tiny native black video, Cloudflare's own pattern
(partytracks sends black video for a device that is off). The video slot
is published at join, and the placeholder fills it in three cases:

- **A voice call**, until it switches to video, which is one way.
- **Camera off**: the camera stops, its light included.
- **The app in the background**, unless a picture-in-picture window keeps
  the camera. Android releases the camera. iOS stops it itself
  (`cameraStopsInBackground`), so the engine keeps the track.

### Quality and data use

The engine samples `getStats()` every few seconds and classifies this
device's connection as good, degraded or poor by incoming loss and RTT. It
moves between tiers with hysteresis, so one bad sample never flaps the
tier.

- **Each tier writes explicit encoder limits** (resolution, frame rate,
  bitrate) to the video sender through `setParameters`, with no
  renegotiation. Weak links lose resolution before smoothness.
- **A remote's `lowBandwidth` caps us at degraded.** We publish it whenever
  our own tier is not good, so one side's struggling downlink stops the
  other from sending more than it can absorb. Audio is never scaled.
- **Low-data calls are on by default, by design** (Settings → Data &
  storage): 360p capture and a 500 kbps cap, so soft video is expected, not
  a bug. The setting is read once per call, since switching mid-call would
  mean re-capturing the camera.

### Encryption

- **One random key per call**, applied per frame with AES-GCM through
  flutter_webrtc's `FrameCryptor`. It is deliberately not the room's
  Megolm session, which follows room membership rather than the call and
  whose ordered ratchet does not suit lossy media.
- **The key travels Olm-encrypted over to-device**, from any device holding
  it to each device that joins. The first valid key wins: one from a
  known, unblocked device of a current participant.
- **The key is never rotated**, since rotating on every departure would
  interrupt everyone's media.
- **Media is gated on keys.** Local tracks stay disabled until their frame
  cryptor exists, and a remote is pulled only once both sides report
  `encrypted`. There is no unencrypted fallback. Until the key lands, the
  call shows "encrypting".

### Call screens

- **One page for the whole call**, always dark. The layout follows the
  call:

  | Situation | Layout |
  |---|---|
  | Waiting, or a one-to-one voice call | Portrait stage: picture, name, one status line |
  | One-to-one, the other camera on | Their camera edge to edge, a self view and floating controls |
  | Three or more people | A two-column grid |

  A new call state extends `CallStatus` and `CallView`, never a new screen.
- **Confirming the other person**: in a one-to-one call, a pill offers to
  confirm someone unconfirmed or changed (`security-verification.md`).
- **Audio route**: a call starts on a connected headset, else the earpiece
  for voice and the speaker for video, and a newly connected headset takes
  the sound. Android selects headsets explicitly, because AudioSwitch
  would otherwise stick to the last chosen device. iOS routes natively, and
  the in-app button follows CallKit's.
- **Screen**: a voice call on the earpiece blanks the screen by proximity,
  and a video call keeps it awake.

### Picture-in-picture

Picture-in-picture shows the other side's camera only, so it is offered
while any remote has video on. Dart picks the person and sends the
window's eligibility, aspect ratio and stream to native code.

| | Android | iOS |
|---|---|---|
| Entry | When the user leaves the app | AVKit's video-call PiP starts on its own |
| Rendering | Flutter draws one remote tile | Native renders the remote track, since the app has no GPU in the background |
| Ending | Hidden when the last remote camera goes off; the call carries on behind its notification | Closed natively (see Gotchas) |

A visible window keeps the camera sending, so the app does not count as in
the background. With "Hide screen content" on, iOS also hides the window's
video while the screen is recorded or mirrored.

### The Android engine during a call

Closing the picture-in-picture window or swiping the task away destroys the
activity, which would take the Flutter engine and the call with it. During
a call `MainActivity` hands the engine to `KeptEngine` instead, and the
call carries on behind `CallForegroundService` until it ends or the system
kills it. The next activity adopts the engine and re-applies its
per-engine state, such as lock-screen display, the wake lock and ringback.

### Ringing

**Rules for both platforms**

| Rule | Why |
|---|---|
| The ringing-call store is written before a ring is presented | Written after, a decline in the gap misses the cancel and the ring sounds on |
| A ring is idempotent per call id across push and sync, and every cancel names its call | Push and sync often deliver the same invite, and one call's end must never take down another's ring |
| A resolved call (summary, decline, answer elsewhere or unanswered ring) never rings again | A late push would otherwise ring a finished call |
| A second call while on one, or while another rings, is auto-declined with a "missed call" notice | Isolates cannot see the active call, so they read a process-wide marker instead |
| A ring ends when another of my devices joins or declines | Nothing about an answer elsewhere pushes, so only sync tells, and sync keeps running during a ring (`app-foundation.md`) |

**Android ring**

- **The `CallStyle` notification is built natively** (`zuno_call_style`),
  since flutter_local_notifications has no `CallStyle` API. Its Accept and
  Decline intents copy that plugin's intent shape, so the plugin's own
  dispatch handles them.
- **A running app also opens `IncomingCallPage`.** A locked phone reaches
  it through the full-screen intent, which needs full-screen-intent access
  (onboarding asks); without it, a locked phone shows only a heads-up
  notification.
- **The ring's sound and vibration are native and process-wide**
  (`IncomingRing`), because Dart audio dies with its engine and freezes
  with the process. Several stops back each other up (cancel, the
  notification's delete intent, Answer, an alarm and a timer), and every
  one names its call.
- **Ringback is a `ToneGenerator` on the voice-call stream**, so it follows
  the earpiece or speaker. It stops when the other side's membership
  appears, not when our own join finishes. Neither the ring nor ringback
  takes audio focus, since the call's own audio session would pause it.
- **Hang up from the ongoing notification or the PiP window** goes to the
  live engine, because teardown needs the live session. Only the ring's
  Decline can run headless.

**Live routes (Android).** A Decline, Reply or Mark as read tap runs in a
separate engine, so it hands the work to the running app first
(`live_isolate_route.dart`). The hand-off is a handshake over named ports,
each step under its own bound, and the sender does the work itself if any
step misses. Only `main.dart`'s `CallNotificationService.initialize()`
claims the routes.

- A busy but alive app must never read as gone, because a second client's
  stale Megolm session can reuse a message index.
- Every path of one action carries one txid, so a timed-out hand-off and
  its fallback never both send.
- A Decline is sent by the notification action engine, by the app, or by a
  push engine that holds while its ring shows. Each marks the call
  resolved and sends through whoever holds the client.

**iOS ring.** Why the server rings a closed Zuno:
[ios-push-and-ring.md](../decisions/ios-push-and-ring.md). Native code owns
CallKit and the audio session (`CallKitCenter.swift`, `CallAudio.swift`),
driven by Dart over `zuno/calls`. The VoIP push transport and the sealed
blob are in `notifications.md`.

```mermaid
sequenceDiagram
  participant P as zuno_push module
  participant N as PushRingHandler (native)
  participant K as CallKit
  participant D as RingCoordinator (Dart)
  P->>N: sealed VoIP push, via Sygnal and APNs
  N->>K: report the call (RingDecision)
  N->>D: ringing event, engine started
  K->>D: answer or decline
```

A running app rings from sync instead, on the same CallKit UUID. Native
events queue until Dart takes them, so a cold-started Dart misses no ring.

`RingDecision` maps each push to one action:

| Push | Action |
|---|---|
| A new call | Rings, named from the room at the preview level (`notifications.md`) |
| Stale, resolved, my own, or forged | Reported, then ended at once |
| Unknown key | A generic ring that Dart binds to the newest recent call or ends, plus a re-registration |
| Before first unlock | A generic ring that stays native; the blob is opened once protected data is available |
| Signed out | Reported, ended, and VoIP pushes turned off |

- **Answering a pushed ring** first re-reads the caller's membership from
  the server, since local state is stale after suspension. CallKit's
  answer is held until Dart reports the call connected.
- **The call ledger** (notify App Group) records each CallKit call's state,
  so a late push never rings a resolved call and the extension can tell
  whether CallKit rang.
- **The extension's fallback ring.** The invite's message push reaches the
  notification extension too. With no ledger entry it waits briefly, then
  shows a time-sensitive fallback ring and asks the module's `ring/status`
  whether a VoIP ring went out; a ring that should not sound becomes a
  quiet call line. Once CallKit shows the ring, the app removes the
  fallback.

| CallKit rule | Why |
|---|---|
| Every VoIP push is reported to CallKit before PushKit's completion; one that must not ring is reported and ended at once | iOS kills an app that returns from a VoIP push without reporting a call |
| A call's UUID is UUIDv5 over room and call id | Sync, push, the extension and Dart all name the same call |
| CallKit is the only ring UI; `IncomingCallPage` shows only when CallKit is unavailable | No double ring UI, and a ring filtered by Focus stays silent |
| The system call follows `activeCallProvider`, not `CallPage` | Nothing renders while locked, so a lock-screen answer may never build the page |
| The audio engine starts only from CallKit's `didActivate`, with flutter_webrtc's own session management off | Audio must start in the session CallKit activates |
| Mute goes through the input mixer and mirrors CallKit's mute | A track mute would outlive the call, and CallKit's mute holds the uplink system-wide |
| A native backstop ends a ring before CallKit's own timeout | CallKit's own end looks like a decline |
| Recents are off, and the handle is an opaque room token | Recents sync through iCloud, and nothing handles a redial |
| Native watchdogs end a stuck call as failed | The engine may never start, and CallKit would otherwise show a dead call |

## Decisions

| Decision | Why |
|---|---|
| SFU only, permanently | Groups need it anyway, and on mobile CGNAT networks peer-to-peer often falls back to a TURN relay regardless |
| Custom signaling, not the SDK's VoIP module | The SDK's `GroupCallSession` hard-codes mesh and LiveKit backends. A LiveKit backend is designed, not built: it would go behind `CallEngine` |
| The module takes the user's Matrix token | Synapse checks it on every request, so nothing is stored and a sign-out revokes at once |
| A placeholder, not separate publish and receive connections (as in partytracks) | Separate connections make every camera toggle a re-publish and a re-pull by every viewer |
| No automatic voice downgrade, and voice to video is one way | A downgrade needs distributed coordination and risks flicker, and an off camera costs little |
| Screen share is not built | Android capture needs its own MediaProjection consent and foreground-service type |
| New mid-call facts ride `fociInfo`; new signaling is an `im.zuno.*` msgtype | Both sides already reconcile `fociInfo`, and a msgtype gets timeline plumbing for free |

## Gotchas

- Nothing over live video clips, blurs or uses `Opacity`, because
  everything there is drawn on every video frame with no raster cache.
- `CallView` slots and `CallGrid` cells are keyed, and End call has no
  long-press tooltip, because a remount or a tooltip drops a press on End
  call.
- `session.engine` is null until the call connects, so the build guards
  it on `connecting`.
- `hangUp()` is memoized rather than phase-guarded, because several
  callers race it and the phase changes only at the end of teardown.
- Every negotiation round goes through `NegotiationLock`, but teardown
  never waits on it, so negotiation re-checks that its connection is still
  live after every await.
- `createOffer` takes explicit empty constraints, because called bare it
  adds receive-only slots that the next pull lands on.
- Never `stop()` a pulled transceiver locally, because Cloudflare hands
  the freed mid to the next pull.
- Every quality tier writes explicit caps, because a null limit never
  reaches Android's encoder and so never lifts a cap.
- RTT comes only from the transport's selected candidate pair, because
  unused TURN relay pairs keep stale RTTs that read as a weak link.
- "Everyone left" needs two empty passes, because a republish can read as
  empty once.
- "Was this call answered" is a flag set once (`everHadRemote`), because a
  departing participant leaves the roster before the auto hang-up checks
  it.
- `m.call.member` must stay in `client.importantStateEvents`
  (`app-foundation.md`), or one side never sees the other join.
- The calls module resolves against `client.homeserver`, the
  well-known-resolved base, not the address typed at login.
- After a flutter_webrtc bump, check the Android placeholder on a device,
  because it reaches plugin internals by reflection and fails quietly.
- iOS sets no codec preferences, because flutter_webrtc's iOS side would
  find the transceiver by its still-empty mid and hit the audio one.
- iOS clears a renderer's `srcObject` shortly before disposing it
  (`videoRendererNeedsDetach`), because flutter_webrtc's iOS renderer
  crashes on queued frames and a crashed app never clears its
  `m.call.member`.
- Re-verify the `CallStyle` intents on a flutter_local_notifications
  major, because they copy its undocumented intent shape and a mis-wire
  fails only on a real tap.
- The foreground service starts first in `CallPage`, because Android
  allows starting one only shortly after user interaction.
- `CallsChannelPlugin` registers only on `EngineHost`'s engine, because
  CallKit state is process-wide and another engine's reset would end the
  app's calls.
- iOS closes the PiP window by clearing its content source, because
  `stopPictureInPicture()` is ignored in the background.
- A `CXSetMutedCallAction` timeout in the log right after a call ends is
  harmless: iOS sent an unmute for a call Zuno had already ended.
- Voices clipping when both talk on loudspeaker are the phone's echo
  canceller, not an app bug, and the earpiece or headphones avoid it.

## Extending

Server-side limits (rate limits, concurrent-call caps, abuse controls)
belong in the `zuno_calls` module, never the client.

## Testing

`CallPage` runs on a `FakeCallSession` (`call_page_harness.dart`) and the
engine on a scripted SFU (`cloudflare_engine_harness.dart`). CallKit tests
run on Linux as iOS through `fake_calls_channel.dart`.
