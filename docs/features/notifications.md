# Notifications

## Overview

Zuno delivers message and call notifications over one of three
interchangeable Android transports, shows messages as Android conversations
(`MessagingStyle`, one thread per room, sender avatars, long-lived
conversation shortcuts), and offers inline Reply and Mark-as-read actions
that run headless. Also covers the new sign-in alert and the unread badge,
which is homeserver-driven, not client-computed.

Call *ringing* presentation (full-screen intent or CallKit, the native ring
player, ringback, the `IncomingCallPresenter` seam), decline routing and the
push handler's ring rules (call waiting, scoped cancels) are in the calls
doc; this doc covers them only where infra is shared.

## Architecture

**`NotificationDeliveryProvider`** (`notification_delivery_provider.dart`)
is the transport abstraction: `start`/`stop`, both idempotent because
`_AuthGate` calls the active provider on every relevant rebuild. One
singleton per `NotificationDeliveryMode`:

| Mode | Provider | Mechanism |
|---|---|---|
| `fcm` (Android default) | `FcmDeliveryProvider` | FCM via Sygnal on the homeserver, received by app-owned Kotlin (FCM pipeline below) |
| `unifiedPush` | `UnifiedPushDeliveryProvider` | Whichever UnifiedPush distributor is installed; the system default distributor is preferred, then the first installed |
| `backgroundService` | `BackgroundSyncDeliveryProvider` | Always-on `/sync` foreground service |
| `apns` (iOS default) | `ApnsDeliveryProvider` | APNs via Sygnal; the token comes over `zuno/apns` (`getToken`) |

**The platform decides which modes exist.** `capabilities.deliveryModes`
(in picker order) and `defaultDeliveryMode` (`app-foundation.md`): android
offers fcm, unifiedPush and backgroundService with fcm as default; ios
offers apns only.
- A stored mode the platform doesn't offer resolves to the platform
  default without rewriting storage.
- `set()`/`autoSelect()` ignore a mode the platform doesn't offer, so
  nothing silently starts a dead transport. `set()` also refuses a mode the
  picker shows disabled (FCM availability below) and returns whether it
  saved.
- **Apple push is gated by `apnsRegistration`** (iOS only). Off,
  `start`/`registerNow` do nothing and the Delivery page shows no status row.
  `stop` touches only what was stored, so stopping it on Android is safe.
- **The token handler is `ApnsTokenPlugin.swift`**, registered as a plugin
  application delegate so the other plugins still see the token callbacks.
  `getToken` calls `registerForRemoteNotifications` and replies the hex
  token, a `FlutterError` on failure, or a timeout error after 30 s so Dart
  never waits forever. It needs the `aps-environment` entitlement, which a
  free Apple team can't sign: until the paid team adds it, registration
  lands on `tokenFailed` with Retry.
- **The iOS pusher's `default_payload`** is an alert "New message" with
  `mutable-content: 1`, so it suits every ring path (plain alert, VoIP from
  the server, or a decrypting extension). Only FCM keeps a recent-pushes log
  (`deliveryLogsEachPush`): it is the one method where app code handles every
  push.
- **The APNs pusher follows Message tone**: `default_payload` carries
  `sound: default` only while it is on. Toggling it re-posts the pusher
  (`messageToneChanged`); start and every resume recheck re-post it when the
  posted value (`push.apns.sound`) differs. A failed re-post keeps the
  registration ready and retries on the next resume.
- **The APNs pushkey is the token bytes in base64**, never the hex the
  handler replies with. Sygnal base64-decodes every pushkey by default, and
  64 hex characters are valid base64 that decode to junk: APNs rejects it and
  the pusher is deleted with no symptom. A non-hex reply is `tokenFailed`.
- **Two Apple app ids, by build mode**: `im.zuno.chat.ios` for release
  (production APNs) and `im.zuno.chat.ios.dev` for debug and profile
  (sandbox), because a token on the wrong environment is rejected and the
  pusher deleted. The registration stores its app id; a relaunch under
  another id or token re-registers and deletes the old pusher.
- **A dropped Apple pusher is counted before it is re-posted**
  (`push.apns.dropped`, persisted): the banner and the Delivery row show it,
  Register, Retry and stop reset it. Sygnal deletes a pusher only after APNs
  rejected its token, so a rising count means wrong environment, topic or
  encoding, and a silent re-post every 6 h would hide exactly that.
- **Firebase is not in the iOS app.** It is a Gradle dependency of the
  Android app module, not a Flutter plugin, so nothing registers it on iOS;
  `FcmBridge` does nothing where FCM is not an offered mode.
- `stopAllNotificationDelivery` still stops every enum value, offered or
  not. It runs *before* `Client.logout()`, which invalidates the token
  before firing `onLoginStateChanged`.

The persisted preference is the name, so reordering is safe.

**Lifecycle hooks in `_AuthGate`** (`app.dart`): `bindAppStateToPushDelivery`
hands both push runners the open room, an "app is resumed and syncing"
predicate and the native "app in front" query, then tells the FCM router
the app engine takes pushes (`markFcmAppReady`, which needs the client
`attachFcmAppClient` set in `main.dart`). `trackPushClientFreshness`
follows the app client's syncs for the push catch-up. A reconnect
(`becameOnline`) calls `retryFailedDelivery`; every resume calls
`recheckDelivery` and re-claims the live routes (calls doc).

**Registration needs the notification permission.** `_AuthGate` starts
the active provider only while `notificationsAllowedProvider` is true, and
every provider re-checks `mayRegisterForNotifications`
(`notification_permission.dart`) itself: FCM in `start`, `registerNow` and
token refresh; UnifiedPush in `start`, `registerNow` and `onNewEndpoint`;
background sync in `start`. That covers the callers that bypass
`_AuthGate`: the Settings Register buttons, `kickOffDeliveryMode` and the
push engines. A failed permission read counts as allowed, so a broken
read never silences delivery. The delivery banner and the Settings rows
for delivery and full-screen alerts are hidden while notifications are off.

**Registration resilience** (`registration_retry.dart`): the push
providers share `RegistrationRetry` (exponential backoff, 1 min doubling to
a 30 min cap, only for transient failures: token/pusher errors, distributor
`network`/`internalError`) and `RegistrationRecheck` (a pusher-list check at
most every 6 h, re-posting a pusher the homeserver dropped). A device that
cannot use FCM and distributor `actionRequired` are never retried.

**FCM availability** (`FcmBridge.availability`, `FcmAvailabilityDecision`):
Firebase configured × Play services status gives `available`,
`updateRequired`, `disabled`, `unavailable`, `notConfigured` (a build
without Firebase config) or `unknown` (a failed check, status -1, an
undocumented code).
- `unknown` counts as usable: it never blocks a registration and never
  moves a registered user.
- A blocked device shows why (`playServicesUpdateRequired`,
  `playServicesDisabled`, `playServicesUnavailable`, `notConfigured`).
  Update and turned-off offer a Fix (`fixPlayServices`: Google's resolution
  flow, then register). A token error `noPlayServices` or `notConfigured`
  is final; `unavailable` and `failed` retry.
- A stored registration is kept on a blocked device. Every resume re-checks
  a Play services block and registers once the device is usable.
- `fcmAvailabilityProvider` (re-read on resume) drives the Settings and
  onboarding pickers: FCM is disabled with the reason while the check runs,
  while Play services is missing or off, and when Firebase is not
  configured. `updateRequired` stays pickable, since choosing it offers the
  update.

**Auto-fallback** (`delivery_auto_fallback.dart`): if FCM reports Play
services missing or turned off, or `notConfigured`, the user never chose a
mode, and no FCM registration exists, the mode flips to UnifiedPush when a
distributor is installed, else background sync. The switch is recorded
under `notificationDeliveryModeAutoKey` and shown once as a dismissable
notice through the delivery banner ("Google services cannot be used, so
notifications use …"). "Chose" means `NotificationDeliveryModeNotifier.set`
ran; a stored mode alone does not count.

**Instant notice** (`PushNotice.kt` in `zuno_notifications`,
`PushNoticeReceiver.kt`, `ZunoPushService.onMessage`): the native side posts
a "New message" notification from the push itself, before any Dart runs:
FCM through `PushNoticeReceiver`, an own `RECEIVE` receiver beside the
Firebase SDK's (priority 999, no `goAsync`), UnifiedPush from the service's
`onMessage`. It posts only when the push has a room and event id, the app is
not in front (`PushNotice.appInFront`: keyguard locked or process below
`IMPORTANCE_FOREGROUND`), nothing is showing for the room, and notify-me is
not mentions-only. The notice uses the room's own notification id and the
`notifications.rooms` name cache, so Dart later replaces it in place or
cancels it (`takePushNotice`, gated by `instantPushNotices`, so iOS never
calls it). The decisions live in `PushNoticeDecision` (pure Kotlin,
JUnit-tested from the app module).

**Push resolution**: every push goes through `HeadlessPushRunner.deliver`
(below) into `handleIncomingPushNotification`. A push with no event id is a
badge push: FCM handles it natively; on UnifiedPush `unread == 0` cancels
every chat notification. Either way only if the gateway sends one:
element-hq/sygnal omits falsy counts and then discards the now-empty badge
push, as does any Sygnal with `send_badge_counts: false`, so there that
clear never arrives and the next sync cleans up instead. Otherwise a
`Client` resolves the event and the handler dispatches to ring, invite,
verification request or message; every "don't notify" exit retracts the
notice for that event. An event that stays undecryptable keeps the "New
message" placeholder unless it is your own.

**One poster for both producers**: the push handler and
`MessageNotificationNotifier` (sync path) both call
`postMessageNotification`. It posts text first, with the sender's avatar
when one is on disk: the notification avatar cache
(`notification_avatar_cache.dart`, keyed by avatar URL), else the
small-bucket avatar the app itself shows (`avatarCacheKey`). It then refines
the same line silently, twice at most: with a fetched avatar on a miss and,
for photos, with the thumbnail published through the `zuno_notifications`
file provider. Where notifications show no sender avatars
(`notificationAvatars` off, iOS) it neither looks one up nor fetches it.

**Presentation** (`call_notification_service.dart`): one notification id
per room, FNV-1a over the room id (`notification_ids.dart`, Kotlin twin
`NotificationIds.kt`, same vectors tested on both sides, because Dart's
`String.hashCode` is not Java's), `MessagingStyle` built from
`notification_thread_store.dart` (last 8 lines per room, in
`SharedPreferences` so every isolate sees them). `showMessage` runs one post
at a time per room and keeps the lines in event-time order. A thread is reset
when its notification is no longer active, so a swiped notification starts
fresh. `shortcutId` is the room id; before each new-message post (not a
placeholder or a refinement) the `zuno_notifications` plugin pushes a
long-lived conversation shortcut, which is what puts the notification in
Android 11's Conversations section. `number` is the room's
`notificationCount`, `when` the event timestamp. The ring is played natively
(calls doc); the message tone is channel-attached (see hardening gotcha).

On iOS, `initialize()` passes `DarwinInitializationSettings` with every
`request*Permission: false`. The plugin prompts at initialization by
default, and without iOS settings it throws, stalling cold start before
`runApp`. Onboarding's `Permission.notification.request()` is the only ask.

iOS posts carry `DarwinNotificationDetails`: `threadIdentifier` is the room,
and the category is `message` (Reply + Mark as read) or `reply` (no event
to mark), registered at `initialize()` with the same action ids as Android,
so one response handler serves both. Both actions run in the background.
A tone plays only for `MessageAlert.tone`; quiet lines and thread updates are
`passive` and list-only (no banner), so they reach the list without lighting
the screen. Active notifications come from the base plugin: Android reports
a `channelId`, iOS only the payload, so a message notification is either one
(`_isMessageNotification`).

**Channels** are grouped; Dart creates its own at `initialize()`, native
services through `NotificationChannels.ensure`, which also creates the group:

| Group | Channels |
|---|---|
| Chats | `direct_messages` (Chat messages), `group_messages` (Room messages), `quiet_messages` (Quiet messages, low importance) |
| Calls | `calls_ringing`, `calls_ringing_group`, `calls_ongoing` (native) |
| Account | `security` (New sign-ins) |
| Background | `background_sync`, `uploads` (both native) |

A thread posts on Quiet messages only while every line in it is quiet.
Retired ids (`messages`, `messages_group`, `messages_sound_v1`,
`messages_group_sound_v1`) are deleted at `initialize()`. Notification
settings shows a row, linking to the channel's system page, for any chat
channel the user turned below default importance.

**Native plugins** (`packages/`): `zuno_vibration` (message vibration
tagged notification usage; the `vibration` package tags every buzz
`USAGE_ALARM`), `zuno_call_style` (the CallStyle ring and its native
player), `zuno_notifications` (instant notice, conversation shortcuts, wake
locks, the client lease, thumbnail file provider). They are real
`FlutterPlugin`s because a hand-attached channel exists only on the engine
that attached it. flutter_local_notifications' action engine, where a ring's
Decline and the message actions run, is a `new FlutterEngine(context)` that
registers every plugin itself; the push engines list these three. On an
engine without the handler a call throws `MissingPluginException`, which the
best-effort callers swallow: no ring, no vibration, no error.

### FCM pipeline (Android)

FCM is app-owned Kotlin in the app module on the Firebase Android SDK:
`PushNoticeReceiver`, `FcmService`, `FcmRouter` (main-thread executor:
jobs, engine boot and destroy, channel sends) over `FcmRouting` (pure,
JUnit-tested state machine), and per engine `FcmChannel` and `FcmPlatform`
(Firebase and Play services calls). Dart reaches it only through
`FcmBridge` over `zuno/fcm`.

**A push, step by step:**
1. The receiver drops duplicates (the last 32 `google.message_id`s) and
   non-data messages (`deleted_messages`, `send_event`): no notice, lock or
   log line. Only an event push (room and event id) gets the instant notice;
   while the app is not in front it also takes a wake lock keyed by the
   message id (30 s) and starts Flutter's loader early.
2. `FcmService.onMessageReceived` handles a badge push natively and hands an
   event push to the router with the native `appInFront` verdict. Its thread
   then waits on the job, 17 s at most, so the process keeps service priority
   (no cached-app freezer) and the SDK's wake lock while Dart works. Then it
   releases the receiver's key and completes the log line.
3. The router sends `push` to an engine; Dart's reply is the ack.

**Routing** (`FcmRouting`):

| Situation | Result |
|---|---|
| App engine attached and ready, or starting within its 10 s grace | It takes every push; pushes queue until it is ready |
| No app takes pushes | The first ready headless engine; with none, one boots (`--fcm-bg`) and pushes queue until its `ready` |
| A headless boot not ready within 12 s | Destroyed, a failed boot. Two failed boots start a 5 min cool-down that finishes queued pushes; the instant notice stands |
| The app attaches, or becomes ready | Idle ready headless engines are retired |
| Headless engine with nothing in flight | Retired after 30 s idle with a ready app, 10 min alone |
| An engine goes with pushes in flight | They are re-sent to another engine; Dart dedupes |
| `push` answered `notImplemented`, or the send throws | Engine marked broken, push re-routed. A broken app is skipped until it detaches; a broken headless engine is retired and counts as a failed boot |
| A push older than 60 s | Finished, never replayed, so no stale ring |

**Retirement waits for quiet.** The router asks the engine `quiescent`,
answered by `HeadlessPushRunner.settle()` (no delivery, queued or held work,
or ring hold; client closed); no answer within 5 s counts as busy. A quiet
engine is destroyed unless queued pushes need it; a busy one goes back to
ready; a broken one is asked again every 30 s, 20 times, then left running.
Why: an engine destroyed mid-write loses that write (app-foundation.md).
Cost: a leaked engine's memory in rare stuck cases.

**`zuno/fcm`**, one handler per engine:

| Direction | Method | Contract |
|---|---|---|
| Dart → native | `ready` | `true` when the router takes this engine; a repeat from the app is a no-op. A headless engine told `false` is not needed and does nothing |
| Dart → native | `getToken`, `deleteToken` | Token, or error `noPlayServices`, `notConfigured`, `unavailable`, `failed` |
| Dart → native | `availability`, `fixPlayServices` | An availability name; the fix runs Google's flow only with a live activity, else answers the current availability |
| native → Dart | `push` `{id, data, appInFront}` | The reply is the ack; an error reply counts as handled; `notImplemented` re-routes |
| native → Dart | `token` `{token}` | The reply is the ack |
| native → Dart | `quiescent` | `settle()`'s answer; asked only of headless engines |

**Badge pushes never reach Dart** (`FcmBadgeDecision`): `unread` 0 while the
app is not in front cancels the notifications on the three chat channels and
drops the thread store key; anything else does nothing. A badge push boots
no engine.

**Token lifecycle:**
- FCM auto-init is off in the manifest; `getToken` turns it on first and
  `deleteToken` turns it off first, so a device on UnifiedPush or background
  sync never talks to Firebase at start.
- The deprecated `getToken()`/`deleteToken()`/`onNewToken` stay (warnings
  suppressed). Their replacement needs the newer opt-in installation-ID
  registration (`firebase_messaging_installation_id_enabled`), judged too new
  for the push path. Cost: a migration in `FcmPlatform` and
  `FcmService.onNewToken` once Google removes them.
- `onNewToken` wakes Dart only when a registration is stored
  (`push.fcm.token`) and differs. The app engine re-posts the pusher through
  `tokenRefreshes`; a push engine moves it with its client
  (`refreshFcmPusherHeadless`). Either deletes the pusher it replaces.
- A move that fails (lease denied, offline) saves the token under
  `push.fcm.pendingToken`. The next push-engine client retries it, and the
  app follows the pending token and the current `getToken` on start and on
  every recheck.

**`onDeletedMessages`** (FCM deleted pending messages) posts one "Some
notifications could not be delivered. Open Zuno to see new messages."
notice (id 4105, `direct_messages`) while notifications are on and the
channel exists.

### Push engines and the runner

**Push engines** (the FCM headless engine, `ZunoPushService`'s UnifiedPush
engine) are `FlutterEngine(context, null, false)` with an explicit plugin
allowlist (`PushEnginePlugins`), not the generated registrant. Some plugins
carry process-wide state: flutter_webrtc stops the shared `AudioSwitchManager`
when its engine detaches, so retiring a push engine that registered it would
cut a live call's audio routing. audioplayers is out too: the ring is native
and voice messages play only in the app. `PushEnginePluginsTest` pins both
the excluded and the required plugins. Cost: a plugin the push path starts
calling must be added, or that engine throws `MissingPluginException`.

**`HeadlessPushRunner`**, one per transport per isolate, owns the client a
push uses:
- **Live client**: in the app engine, the app's own client (`liveClient`),
  used directly.
- **Burst client**: in a push engine, opened on demand by
  `createMatrixClient(backgroundSync: false)` under a background lease
  (`app-foundation.md`), its users serialized by one queue. It stays open
  across pushes until the app asks for the lease (yield), the router settles
  the engine, or the engine ends; UnifiedPush also closes it after 10 min
  idle. Why: the lease makes the client exclusive, and spaced pushes skip
  `Client.init` and its catch-up sync. Cost: tens of MB held in a cached
  process for up to 10 min. A new burst client opens only once the previous
  one has finished closing.
- The FCM engine sends `ready` before its notification setup is done, and
  pushes wait on that setup; an event push starts opening the burst client
  on arrival, alongside it.
- `deliver` returns at the first visible outcome. Avatar and thumbnail
  refinement is handed off (`onRefining`) and keeps the burst client plus its
  own `zuno/wake_lock` tag (8 s cap), so the ack never waits for it.
- `deliver` drops a push when the app is resumed, syncing and really in
  front (the verdict that came with an FCM push, else `zuno/push_wakelock`'s
  `appInFront`; a failed ask counts as in front). A locked keyguard is never
  in front, so a hang-up push still stops a ring shown over the lock screen.
  It also drops a push for a signed-out client (notice retracted) and on
  `ClientLeaseDenied` (notice kept).
- `settle()` closes an idle client and reports whether the runner is
  quiescent. The FCM ring hold (`onRinging`, calls doc) counts against
  quiescence and lets its client go on yield.

### iOS responses, background time and room opens

Runner is the `UNUserNotificationCenter` delegate (`AppDelegate.swift`) and
completes every `willPresent` and `didReceive` exactly once
(`OnceCompletion` around `super`). flutter_local_notifications (FLN)
completes its own notifications synchronously, so a response still open
after `super` is one no live plugin took: a remote APNs alert, or a local
one after iOS terminated the app.

| Not taken | Handling |
|---|---|
| `willPresent` | A remote push shows nothing in the foreground (`[]`): the running app posts from sync. A local one shows as banner and list |
| Tap | Opens its room through `RoomLaunchPlugin` |
| Reply with text | Posts "Message not sent. Open Zuno and send it again." in that chat's thread; its tap opens the room |
| Mark as read, dismiss | Completed; nothing is sent |

- **`RoomLaunchPlugin`** is iOS's half of `zuno/shortcuts`, gated by
  `nativeRoomOpens`: `openRoom` while Dart listens, else held for
  `takeLaunchRoomId` at launch.
- **`WakeLockPlugin`** serves `zuno/wake_lock` as tag-keyed background tasks
  (`beginBackgroundTask`, each with its own timeout) and
  `zuno/push_wakelock` (`release` is a no-op, `appInFront` is "app active"),
  so `headlessWakeLocks` is on for iOS. A local notification's custom action
  holds a 10 s native bridge task until Dart takes its own lock.
- **The action engine registers seven plugins, not the generated
  registrant** (`registerActionEnginePlugins`: FLN, secure storage,
  package_info_plus, shared_preferences, sqflite_sqlcipher, `WakeLockPlugin`,
  `ClientLeasePlugin`). The full registrant flipped the shared audio
  session, cutting a voice recording, and replaced flutter_webrtc's
  singleton. Cost: a plugin the Dart action path starts calling must be
  added there, or that isolate throws `MissingPluginException`.

## Data & State

- **Unread counts** come from `room.notificationCount`, homeserver-driven.
  Timeline-hidden messages the server still counts (call invite,
  verification request, a summary without a relation) are subtracted by
  `callUnreadCorrectionProvider`; events with an `m.reference` relation are
  never counted, so never corrected.
- **Notified event ids** (`notified_events_store.dart`): last 256 ids
  `showMessage` posted, plus `placeholder:` markers. A real post records
  the id; a placeholder records the marker only.
- **Threads** (`notification_thread_store.dart`): per-room title, kind and
  lines (`eventId`, sender, text, timestamp, avatar URL, image URI,
  `placeholder`, `quiet`), one prefs key for all rooms. Cleared by
  `cancelMessageNotification`, by a post that takes a notice (the notice
  makes the room look "showing"), and by FCM's native badge clear.
- **Room-name cache** (`notification_room_cache.dart`): `notifications.rooms`,
  one `roomId<TAB>d|g<TAB>name` line per joined room, rebuilt on the first
  sync of a process and on syncs carrying room state, a leave or `m.direct`,
  written only when changed. Read natively from `FlutterSharedPreferences`.
- **Notices** are process-local, room → event id; `takePushNotice(roomId,
  eventId)` returns true once, only for that event.
- **Avatar cache**: files under `notification_avatars/` in app support,
  named by the base64 of the avatar URL, so a changed avatar is a miss.
- **Sound settings**: raw `SharedPreferences` keys, not
  `app_preferences_provider.dart`, because the headless sound player has
  no provider scope. A test pins both sides key-for-key.
- **Delivery mode**: `settings.notification_delivery_mode`, plus a
  `_chosen` flag and the `_auto` marker described above.
- **FCM registration**: `push.fcm.token`, plus `push.fcm.pendingToken` for a
  token a push engine could not register.
- **UnifiedPush registration**: endpoint, gateway, and, for a WebPush
  pusher, the p256dh pushkey and auth secret.
- **Announced invitations** (`notifications.announced_invites`):
  `rooms-membership.md`.
- **Failed sends** retry once on the offline→online edge, session-scoped.
- **Delivery log** (`push.recent_deliveries`, `PushDeliveryLog.kt` /
  `push_delivery_log.dart`): one tab-separated line per FCM data push,
  newest first, 50 kept, written off the main thread with `apply()`.
  `PushNoticeReceiver` writes columns 1–8, and `FcmService` rewrites that
  line with 9–11:

  | Columns | Hold |
  |---|---|
  | 1–2 | Received and sent time (ms) |
  | 3–4 | Original and delivered priority |
  | 5–6 | Device idle, standby bucket |
  | 7–8 | Time spent in the receiver (ms), notice posted |
  | 9–11 | Service start (ms after receipt), handling (`dart`, `clear`, `none`), Dart's ack (ms after receipt) |

  Push target → Recent pushes reads the first six and accepts any longer
  line; the timing columns exist to measure release builds. A downgrade
  reads as `high` sent, `normal` delivered.

## Communication

- **Push payload is `event_id_only`**, a privacy choice; every push costs a
  fetch. Sygnal's FCM v1 pushkin flattens counts to top-level strings
  (`unread: "3"`), which `pushNotificationFromFcmData` parses; a badge push
  has counts and no event id.
- **The gateway is the homeserver's own host**: the FCM and APNs pushers
  (and the UnifiedPush WebPush option) point at
  `https://<homeserver host>[:port]/_matrix/push/v1/notify` (`fcmGatewayUri`,
  from the `.well-known`-resolved `client.homeserver`).
- **`getEventByPushNotification` contract**: `null` means nothing to show
  (must stay silent: already read elsewhere); a throw means the fetch
  failed and is the only case that keeps the "New message" placeholder.
- **Server push rules** (`server_push_rules.dart`): two override rules
  with no actions on `content.m\.relates_to.rel_type`,
  `im.zuno.encrypted_reaction` (`m.annotation`) and `im.zuno.reference`
  (`m.reference`). `m.relates_to` is cleartext even in encrypted events,
  so Synapse stops pushing encrypted reactions, call declines, answered-call
  summaries and in-room verification follow-ups, none of which show a
  notification. Edits are covered by the default `.m.rule.suppress_edits`.
  `.m.rule.message` also gets a `sound` tweak: Synapse marks unencrypted
  events without sound or highlight low priority, which Sygnal sends as FCM
  normal and Doze holds. `event_id_only` drops tweaks, so only the priority
  changes; other clients on the account ring for those rooms.
- **Pushers**: `PusherGroups` shows every other pusher as one list; the
  current session is matched by pushkey.
- **Notification actions** (Reply, Mark as read) run in FLN's action engine
  (`runHeadlessMessageAction`) with a per-run `zuno/wake_lock` tag (30 s,
  re-taken before each fallback) and one txid. They go to the app's live
  action route first (protocol in the calls doc), where
  `HeadlessMessageActionNotifier` performs them with the app's client, once
  per txid. With no live app they open a one-shot client under a background
  lease; a denied lease retries the hand-off for about 6 s. The network call
  is retried twice (2 s, 5 s) and the client disposed with
  `closeDatabase: false`. A Reply that sends nothing throws, so it is
  retried rather than reported done.
- **New sign-in alerts** diff `client.userDeviceKeys` against a local store
  on every sync tick.
- **UnifiedPush WebPush** (`unifiedPushViaHomeserverGateway`, off): with a
  key set from the distributor, register a pusher keyed by the p256dh key
  with `endpoint` and `auth` in its data, pointed at the homeserver's own
  Sygnal instead of a third-party Matrix gateway. Needs a WebPush pushkin
  for `im.zuno.chat.unifiedpush` in Sygnal first.

## Key Design Decisions

- **FCM is app-owned Kotlin, not the Flutter Firebase plugins.** A Flutter
  plugin compiles into the iOS app too, and `firebase_messaging` builds its
  background engine internally, so the app could not route a push to the
  running app, retire that engine, choose its plugins or hold the service
  while Dart works. The code sits in the app module, not a local plugin: the
  app builds both engines' channels, the receiver/wake-lock pairing needs
  app-module classes, and the JUnit tests live there.
- **Pushes go to the running app first.** While the app holds the client
  lease, a push engine cannot open a client at all, and the app's warm
  client skips an engine boot and `Client.init`. The 10 s grace covers a cold
  start where the engine is attached but Dart is not ready yet.
- **No foreground service on the cold push path.** Its gain is unmeasured,
  Play's foreground-service policy applies, and work past the deferral
  would show a visible notification; the delivery log's timing columns are
  there to measure it. Cost: the cold path stays in the background CPU
  class.
- **Notification actions stay in Dart.** A native renderer would mean
  re-implementing `MessagingStyle` and `RemoteInput`, a subsystem rewrite,
  and the client lease already makes the action engine's client safe. Cost:
  the first action in a process boots FLN's engine.
- **The ack waits until the notified-event marks are on disk.** Acking
  earlier would save tens of ms but risks posting the same event twice.
- **The push runner refreshes the access token before any action.**
  `HeadlessPushRunner.withClient` calls `ensureNotSoftLoggedOut` first,
  bounded to 10 s (`freshTokenBound`), after which the push goes on.
  Fetching a push event refreshes on its own, but re-registering a pusher
  after an endpoint change does not, and that failing silently costs all
  notifications until the app is opened again.
- **FCM first, UnifiedPush, then background sync.** Only a high-priority
  FCM message earns a temporary power allowlist per delivery. Both
  fallbacks depend on a battery exemption; the UnifiedPush one also needs
  the *distributor* exempt, which `distributorBatteryRestricted` checks
  (`PowerManager.isIgnoringBatteryOptimizations` accepts any package) and
  onboarding, Settings and the banner surface.
- **Notice before Dart, whenever the app is not in front.** Cold
  arrival-to-screen measured 5.7 s (process, engine, database, client init,
  fetch); the notice lands at process start. Gating on "no engine alive"
  would leave most pushes to Dart, since an engine often stays up between
  pushes. Dart posts silently over a notice for the same event only while it
  is still showing, so a dismissed notice or one for another event never
  mutes an alert, and a notice counts toward the tone rate limit
  (`recordNoticeAlert`) so the next line in that room does not chime again.
- **Post first, refine later.** After 3 s (`defaultPlaceholderAfter`) of
  unresolved fetch the handler posts a routable "New message" placeholder
  named after the local room. The real content replaces the line silently
  (`onlyAlertOnce`); a null resolution retracts it; a failed fetch leaves it
  as the fallback. A placeholder never records the event id, so the catch-up
  sync upgrades it, but it records a marker, so an event whose placeholder
  the user already dealt with is never re-posted.
- **A stale app client catches up beside the fetch.** When the app's client
  has not synced for 15 s and no sync runs, a push starts a zero-timeout sync
  alongside the event fetch. A message waits up to 1.5 s for it and stays
  silent if it shows the event read on another device; rings, invites and
  hang-ups never wait. The fetched event is stored only when no sync is
  pending or catching up.
- **Every high-priority push should end in a notification.** FCM
  deprioritizes an app instance whose high-priority messages repeatedly
  produce none (7 days of behavior). Silent consumers are kept off the push
  path by the relation rules, or made visible: mentions-only posts other
  messages on Quiet messages, an undecryptable push keeps "New message", a
  verification request notifies. The already-read null path and declined
  summaries (their push stops a ring on the user's other devices) still
  consume silently.
- **Mentions-only posts other messages quietly**, on the push path and on
  the sync path while the app is not in front; never while it is. A quiet
  placeholder that resolves to a mention alerts on the upgrade.
- **The headless client's catch-up `/sync` stays.** `Client.init` always
  runs one and the SDK cannot skip it; discarding it wastes the download
  and makes the app fetch it again, and it brings the room keys decryption
  needs. Keeping the burst client open makes it one per burst, not one per
  push. Debug builds log `zuno/push: timing` (with
  `init`/`prefs`/`thread`/`sound`/`avatars`/`shortcut`/`show`/`store`
  marks on the first post) and `client timing` lines to size this.
- **The threads stay one prefs key.** A cross-isolate race can lose a line,
  which is cosmetic, and FCM's native badge clear drops the one key.
- **`MessagingStyle` over `BigPicture`.** A conversation needs
  `MessagingStyle`, a `Person` and a long-lived shortcut; a photo is shown
  as an image on its line through a content URI, so nothing is lost.
- **No explicit group summary.** Mark-as-read cancels the chat notification
  natively, before Dart runs, and Android shows a childless summary as an
  ordinary "New messages" notification until something removes it. Android
  bundles four or more chats on its own with a system summary. An explicit
  "Zuno" bundle below four needs the native message-notification route.
- **`ensureVodozemacInitialized()` remembers success only**, so a failed
  init is retried by the next push.
- **A message notifies once, whichever path posts first**, through the
  notified-events store; a post with no event id (invite) is never deduped
  there.
- **The sync path ignores the initial sync** (`prevBatch == null`), so a
  cache clear cannot replay weeks-old messages as new.
- **New sign-in alerts fire for every new device, verified or not**, on a
  `security` channel that chat-mute cannot silence, with exactly one
  resolving button.

## Gotchas & Constraints

- **The homeserver's reverse proxy must route `/_matrix/push/v1/notify` to
  Sygnal.** Without that route Synapse answers the path itself with a 404:
  every push is dropped, the pusher still posts, and the app shows "Active.
  Receiving notifications."
- **A notification-permission revoke kills the process**, so the next
  launch's `stop` knows only the persisted registration. Both push
  providers' `stop` fall back to it; without that the pusher stays on the
  homeserver.
- **Background audio hardening mutes app-process sound** once the process
  has no visible activity; a channel's own sound is played by the system
  and is exempt. One-shot sounds go on a channel; the looping ring is played
  by the app and relies on the full-screen activity.
- **Never reuse a retired channel id**; recreating restores old settings.
  A channel's sound is fixed at creation, and its group can be set only
  while it has none.
- **A same-room burst must not re-post silently while the tone plays**:
  `messageAlertFor` returns `silentUpdate` for the same room (mutes via
  `onlyAlertOnce` without clearing the sound) and `silent` for another.
- **`UnifiedPush.initialize()` is a no-op on Linux**, so the provider
  registers callbacks through `UnifiedPushPlatform.instance` directly;
  otherwise test fakes never receive `onNewEndpoint`.
- **Two plugins declaring `androidx.core.content.FileProvider` collide at
  manifest merge** (image picker and share already do), which is why the
  thumbnail provider is the `NotificationFileProvider` subclass with its
  own authority.
- **`event_id_only` needs a network round trip under Doze**; a declined
  exemption has no client-side fix beyond the placeholder.
- **The FCM ack must not wait on a ring hold.** `onMessageReceived` waits for
  Dart's reply and the service handles one message at a time, so the ring
  hold runs beside the ack (`onRinging`), never inside it, or the hang-up
  push would wait behind it up to the 17 s cap. The receiver's keyed wake
  lock, like any wake lock, holds in Doze only inside the FCM allowlist
  window.
- **UnifiedPush's bound-service delivery holds no wakelock**;
  `ZunoPushService` (replacing the connector's service via
  `tools:node="remove"`) takes a hold keyed by the event id on one 30 s
  lock for every push, whichever engine handles it. The Dart isolate that
  handled the push releases its key after `deliver`, and the lock drops once
  no hold younger than 30 s remains. `Plugin.count` is an id allocator, not a
  liveness signal; the generation comparison in `PushEngineDecision` detects
  a superseded headless engine, which is retired only once quiet, like FCM's.
- **A UnifiedPush notification can be lost before Dart runs** if the
  connector's `RaiseToForegroundService` bind stalls past the service
  watchdog. Part of why FCM is the default.
- **`ZunoPushService.onCreate` boots the engine before `onMessage`**,
  synchronously on the main thread, so on UnifiedPush the notice waits
  behind it (measured 2.8 s cold versus 0.9 s on FCM). The connector boots
  its engine in `onCreate`, so deferring it needs a fork of the connector.
- **The notice never creates a channel** (Dart owns them, including the
  custom tone); a missing channel means no notice. It alerts through the
  channel's own sound and vibrates by hand, since message channels are
  `playSound: true, enableVibration: false`. The hand vibration carries
  notification usage: Android 12+ drops background vibrations of any other
  usage. An uncached room posts plain
  on `direct_messages` and is replaced when Dart knows better; a known room
  posts as a conversation with its shortcut, so it does not jump sections.
- **A call or invite push gets the notice first**: the invite carries the
  push's event id and replaces it silently; the ring is presented first and
  the notice retracted after, since `event_id_only` carries no event type.
- **On iOS, "not taken" means FLN did not complete synchronously**, not an
  engine flag, which goes stale when iOS frees the scene's engine. An FLN
  that completes asynchronously would post false "not sent" notices:
  re-check on every FLN upgrade.
- **`pushConversationShortcut` stays ungated on iOS** for the planned
  `INSendMessageIntent` half (`docs/plan-ios-native.md`); until then each
  new-message post swallows one `MissingPluginException` there.
- **Fire-and-forget network calls are not error-free**; wrap best-effort
  work in `runBestEffort`.
- **Background sync runs as `specialUse` on Android 14+**
  (`BackgroundSyncDecision`): Android 15 caps `dataSync` foreground services
  at 6 h a day and crashes the app when one outlives it.
- **`NotificationCompat.CallStyle` throws on a blank `Person` name**; both
  call builders fall back to a non-empty string.
- **A refinement for a thread the user dismissed is dropped**, never
  re-posted; the thread check is what decides.
- **A room read while its sync-path post is in flight is cleared after that
  post lands**: `MessageNotificationNotifier` waits for the room's pending
  first posts before canceling, so a late post cannot outlive the read.

## Extension Guidance

- **New transport**: implement `NotificationDeliveryProvider` with
  `retryIfFailed` and `recheckRegistration`, add the enum value, wire
  `notificationDeliveryProviderFor`, `retryFailedDelivery`,
  `recheckDelivery` and `deliveryDependsOnBatteryExemption`, and list it
  in the platform's `deliveryModes` in `capabilitiesFor`.
- **New producer of message notifications**: build a
  `MessageNotificationContent` and call `postMessageNotification`; never
  `showMessage` directly.
- **New headless notification action**: route it through the existing
  dispatcher, give it a distinguishing payload shape, keep it unawaited if
  it must hold the isolate, and follow `runHeadlessMessageAction`: a per-run
  wake-lock tag, one txid, the live route first, `clientOrPatientHandOff`
  for the client. On iOS every plugin it calls must be in
  `registerActionEnginePlugins`.
- **Anything a push engine calls**: add its plugin to `PushEnginePlugins`,
  and keep plugins with process-wide side effects out.
- **Anything needing payload content**: assume `event_id_only`.
- **Anything about server push rules**: add to
  `PushRuleMaintenanceNotifier` (`server_push_rules.dart`), which runs once
  the rules have synced.
- **An event that must never notify**: give it a cleartext relation, such
  as `m.reference` to a related event, rather than a new rule.

## Dependencies / Integration

- **Calls**: the sound toggles, the headless action dispatcher and the live
  routes; the ring's tone and vibration play natively, and ring presentation
  and decline routing are in the calls doc.
- **App foundation**: the client lease, background clients and the shared
  database the push engines open (`app-foundation.md`).
- **Event display**: `event_display.dart` is the source of truth for a
  notification's text and whether an event is a photo.
- **Security**: the new-sign-in alert reads `client.userDeviceKeys` the
  same way `lib/core/security/` does.
- **Onboarding**: `OnboardingStep.batteryExemption` is queued when
  `needsBatteryExemptionFor` says so, which for UnifiedPush includes the
  distributor's own exemption; `OnboardingStep.autostart` once, on phones
  where a maker's autostart screen resolves (`AutostartDecision.availableFor`).
  The vendor packages are in the manifest's `<queries>`, or Android 11+
  hides them and nothing resolves. A custom ROM on that hardware (LineageOS)
  has no such screen and gets neither the step nor the Settings row.
- **Settings**: `notifications_settings_page.dart` for the permission,
  sound toggles and silenced-channel rows; `notification_delivery_page.dart`
  for mode choice and the transport rows, including the battery row (every
  Android mode) and Autostart; `push_target_status_page.dart` for pusher management
  and Recent pushes.
