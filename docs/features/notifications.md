# Notifications

## Overview

Zuno delivers message and call notifications over one of three
interchangeable transports, shows messages as Android conversations
(`MessagingStyle`, one thread per room, sender avatars, long-lived
conversation shortcuts), and offers inline Reply and Mark-as-read actions
that run headless. Also covers the new sign-in alert and the unread badge,
which is homeserver-driven, not client-computed.

Call *ringing* presentation (full-screen intent, ringback, the
`showIncomingCall`/`cancelIncomingCall` lifecycle) is in the calls doc; this
doc covers it only where infra is shared.

## Architecture

**`NotificationDeliveryProvider`** (`notification_delivery_provider.dart`)
is the transport abstraction: `start`/`stop`, both idempotent because
`_AuthGate` calls the active provider on every relevant rebuild. One
singleton per `NotificationDeliveryMode`:

| Mode | Provider | Mechanism |
|---|---|---|
| `fcm` (default) | `FcmDeliveryProvider` | FCM via Sygnal on the homeserver |
| `unifiedPush` | `UnifiedPushDeliveryProvider` | Whichever UnifiedPush distributor is installed; the system default distributor is preferred, then the first installed |
| `backgroundService` | `BackgroundSyncDeliveryProvider` | Always-on `/sync` foreground service |

Enum order is the Settings picker order; the persisted preference is the
name, so reordering is safe. `stopAllNotificationDelivery` runs *before*
`Client.logout()`, which invalidates the token before firing
`onLoginStateChanged`.

**Lifecycle hooks in `_AuthGate`** (`app.dart`): `bindAppStateToPushDelivery`
hands both push runners the open room and an "app is resumed and syncing"
predicate; a reconnect (`becameOnline`) calls `retryFailedDelivery`; every
resume calls `recheckDelivery`.

**Registration resilience** (`registration_retry.dart`): both push
providers share `RegistrationRetry` (exponential backoff, 1 min doubling to
a 30 min cap, only for transient failures: token/pusher errors, distributor
`network`/`internalError`) and `RegistrationRecheck` (a pusher-list check at
most every 6 h, re-posting a pusher the homeserver dropped). Play Services
missing/outdated and distributor `actionRequired` are never retried.

**Auto-fallback** (`delivery_auto_fallback.dart`): if FCM reports
`playServicesUnavailable` and the user never chose a mode, the mode flips to
UnifiedPush when a distributor is installed, else background sync. The
switch is recorded under `notificationDeliveryModeAutoKey` and shown once as
a dismissable notice through the delivery banner. "Chose" means
`NotificationDeliveryModeNotifier.set` ran; a stored mode alone does not
count.

**Instant notice** (`PushNotice.kt` in `zuno_notifications`,
`PushNoticeReceiver.kt`, `ZunoPushService.onMessage`): on a cold process the
native side posts a "New message" notification from the push itself, before
any Dart runs: FCM through an own `RECEIVE` receiver beside the Firebase
plugin's (priority 999, no `goAsync`), UnifiedPush from the service's
`onMessage`. It posts only when the push has an event id, no Flutter engine
is alive in the process (`ZunoNotificationsPlugin` counts attach/detach),
nothing is showing for the room, and notify-me is not mentions-only. The
notice uses the room's own notification id and the `notifications.rooms`
name cache, so Dart later replaces it in place or cancels it. The decisions
live in `PushNoticeDecision` (pure Kotlin, JUnit-tested from the app module).

**Push resolution**: every push goes through `HeadlessPushRunner.deliver`.
A push while the app is resumed and syncing is dropped (the sync path posts
it). A push with no event id is a badge push; `unread == 0` cancels every
chat notification — if the gateway sends one. element-hq/sygnal omits falsy
counts and then discards the now-empty badge push, as does any Sygnal with
`send_badge_counts: false`, so there that clear never arrives and the next
sync cleans up instead. Otherwise a `Client` shared by the queued burst
resolves the event and `handleIncomingPushNotification` dispatches to ring,
invite or message; every "don't notify" exit retracts the notice for that
event.

**One poster for both producers**: the push handler and
`MessageNotificationNotifier` (sync path) both call
`postMessageNotification`, which posts text first and then refines the
same line silently, twice at most: with the sender's avatar (disk cache
keyed by avatar URL, `notification_avatar_cache.dart`) and, for photos,
with the thumbnail published through the `zuno_notifications` file provider.

**Presentation** (`call_notification_service.dart`): one notification id
per room, FNV-1a over the room id (`notification_ids.dart`, Kotlin twin
`NotificationIds.kt`, same vectors tested on both sides, because Dart's
`String.hashCode` is not Java's), `MessagingStyle` built from `notification_thread_store.dart`
(last 8 lines per room, in `SharedPreferences` so both isolates see them).
A thread is reset when its notification is no longer active, so a swiped
notification starts fresh. `shortcutId` is the room id and the
`zuno_notifications` plugin pushes a long-lived conversation shortcut
before every post, which is what puts the notification in Android 11's
Conversations section. `number` is the room's `notificationCount`, `when`
the event timestamp. The ring is app-played (loops); the message tone is
channel-attached (see hardening gotcha).

**Native plugins** (real `FlutterPlugin`s so they reach every engine,
including `firebase_messaging`'s own and the local-notifications action
engine): `zuno_vibration` (vibration), `zuno_call_style` (CallStyle ring),
`zuno_notifications` (instant notice, conversation shortcuts, headless wake
locks, thumbnail file provider). A hand-attached channel exists only on the engine that
attached it; a push arrives with the app process dead.

## Data & State

- **Unread counts** come from `room.notificationCount`, homeserver-driven.
  An answered call's summary is excluded via a power-level push rule.
- **Notified event ids** (`notified_events_store.dart`): last 256 ids
  `showMessage` posted, plus `placeholder:` markers. A real post records
  the id; a placeholder records the marker only.
- **Threads** (`notification_thread_store.dart`): per-room title, kind and
  lines (`eventId`, sender, text, timestamp, avatar URL, image URI,
  `placeholder`). Cleared by `cancelMessageNotification`, and by a post
  that takes a notice (the notice makes the room look "showing").
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
- **UnifiedPush registration**: endpoint, gateway, and, for a WebPush
  pusher, the p256dh pushkey and auth secret.
- **Failed sends** retry once on the offline→online edge, session-scoped.

## Communication

- **Push payload is `event_id_only`**, a privacy choice; every push costs a
  fetch. Sygnal's FCM v1 pushkin flattens counts to top-level strings
  (`unread: "3"`), which `pushNotificationFromFcmData` parses; a badge push
  has counts and no event id and is kept, not dropped.
- **`getEventByPushNotification` contract**: `null` means nothing to show
  (must stay silent: already read elsewhere); a throw means the fetch
  failed and is the only case that keeps the "New message" placeholder.
- **Server push rules** (`encrypted_reaction_push_rule.dart`): the client
  installs one override rule, `im.zuno.encrypted_reaction`, matching
  `content.m\.relates_to.rel_type == m.annotation` with no actions.
  `m.relates_to` is cleartext even in encrypted events, so Synapse stops
  pushing encrypted reactions, which `.m.rule.reaction` cannot see.
  Edits are already covered by the default `.m.rule.suppress_edits`.
- **Pushers**: `PusherGroups` shows every other pusher as one list; the
  current session is matched by pushkey.
- **Notification actions** run through the local-notifications headless
  dispatcher, hold a 30 s wake lock from `zuno_notifications`, retry the
  network call twice, and use a one-shot client disposed with
  `closeDatabase: false`.
- **New sign-in alerts** diff `client.userDeviceKeys` against a local store
  on every sync tick.
- **UnifiedPush WebPush** (`unifiedPushViaHomeserverGateway`, off): with a
  key set from the distributor, register a pusher keyed by the p256dh key
  with `endpoint` and `auth` in its data, pointed at the homeserver's own
  Sygnal instead of a third-party Matrix gateway. Needs a WebPush pushkin
  for `im.zuno.chat.unifiedpush` in Sygnal first.

## Key Design Decisions

- **The headless runner refreshes the access token before any action.**
  `HeadlessPushRunner.withClient` calls `ensureNotSoftLoggedOut` first.
  Fetching a push event refreshes on its own, but re-registering a pusher
  after an endpoint change does not, and that failing silently costs all
  notifications until the app is opened again.

- **FCM first, UnifiedPush, then background sync.** Only a high-priority
  FCM message earns a temporary power allowlist per delivery. Both
  fallbacks depend on a battery exemption; the UnifiedPush one also needs
  the *distributor* exempt, which `distributorBatteryRestricted` checks
  (`PowerManager.isIgnoringBatteryOptimizations` accepts any package) and
  onboarding, Settings and the banner surface.
- **Notice before Dart.** Cold arrival-to-screen measured 5.7 s (process,
  engine, database, client init, fetch); the notice lands at process start.
  Dart posts silently over a notice for the same event only while it is
  still showing, so a dismissed notice or one for another event never mutes
  an alert. Warm processes get no notice: Dart is under a second there.
- **Post first, refine later.** After 3 s (`defaultPlaceholderAfter`) of
  unresolved fetch the handler posts a routable "New message" placeholder
  named after the local room. The real content replaces the line silently
  (`onlyAlertOnce`); a null resolution retracts it; a failed fetch leaves it
  as the fallback. A placeholder never records the event id, so the catch-up
  sync upgrades it, but it records a marker, so an event whose placeholder
  the user already dealt with is never re-posted.
- **Every high-priority push should end in a notification.** Android 13+
  downgrades an app's high-priority FCM messages when they repeatedly
  produce none, which is the `PUSH_MESSAGING_DEFERRABLE` delay. The
  reaction push rule removes the largest silent consumer and the notice
  makes the correlation immediate. Mentions-only mode (no notice, by design)
  and the already-read null path still consume silently.
- **`MessagingStyle` over `BigPicture`.** A conversation needs
  `MessagingStyle`, a `Person` and a long-lived shortcut; a photo is shown
  as an image on its line through a content URI, so nothing is lost.
- **No explicit group summary.** Mark-as-read cancels the chat notification
  natively, before Dart runs, and Android shows a childless summary as an
  ordinary "New messages" notification until something removes it. Android
  bundles four or more chats on its own with a system summary. An explicit
  "Zuno" bundle below four needs the native message-notification route.
- **The client's lifetime is the burst's, and its build starts before the
  push is read.** Both headless entries call `prepareHeadlessPush`: the FCM
  handler as its first statement, the UnifiedPush entry
  (`unified_push_headless_entry.dart`) right after registering the connector
  callbacks. It starts the `Client` build (in-isolate crypto, no `compute`)
  and overlaps it with the notification-service init; vodozemac is
  initialised inside `createMatrixClient`, and the background isolate never
  initialises Firebase (nothing there uses it). The runner keeps the client
  while more pushes are queued, disposes it when the queue drains, and
  disposes a prepared client no push needed; the native side keeps the
  engine alive across pushes. Debug builds log `zuno/push: timing` (with
  `init`/`prefs`/`thread`/`sound`/`avatars`/`shortcut`/`show`/`store`
  marks on the first post) and `client timing` lines to size this. Measured
  cold: the wait between Dart starting and the client build starting went
  from 2.5 s to nothing.
- **`ensureVodozemacInitialized()` remembers success only**, so a failed
  init is retried by the next push.
- **A message notifies once, whichever path posts first**, through the
  notified-events store; a post with no event id (invite) is never deduped.
- **The sync path ignores the initial sync** (`prevBatch == null`), so a
  cache clear cannot replay weeks-old messages as new.
- **New sign-in alerts fire for every new device, verified or not**, on a
  `security` channel that chat-mute cannot silence, with exactly one
  resolving button.

## Gotchas & Constraints

- **Background audio hardening mutes app-process sound** once the process
  has no visible activity; a channel's own sound is played by the system
  and is exempt. One-shot sounds go on a channel; the looping ring stays
  on `audioplayers` and relies on the full-screen activity.
- **Never reuse a retired channel id**; recreating restores old settings.
  A channel's group and sound are fixed at creation.
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
- **UnifiedPush's bound-service delivery holds no wakelock**;
  `ZunoPushService` (replacing the connector's service via
  `tools:node="remove"`) takes a 30 s one, released from Dart, gated on
  `PushEngineDecision.shouldHoldWakeLock`. `Plugin.count` is an id
  allocator, not a liveness signal; the generation comparison in
  `PushEngineDecision` detects a superseded headless engine.
- **A UnifiedPush notification can be lost before Dart runs** if the
  connector's `RaiseToForegroundService` bind stalls past the service
  watchdog. Part of why FCM is the default.
- **`firebase_messaging` handles background pushes serially** behind a
  `JobIntentService` latch; a ring-decline hold must run unawaited or it
  blocks the hang-up push behind it. Its engine boots in that service, after
  both receivers return, which is why the FCM notice sees a cold process.
- **`ZunoPushService.onCreate` boots the engine before `onMessage`**, so the
  live-engine count is never zero there; the service snapshots coldness in
  `onCreate` (`PushNoticeDecision.enginesFor`) for its first message only.
  That boot is synchronous on the main thread, so on UnifiedPush the notice
  waits behind it (measured 2.8 s cold versus 0.9 s on FCM); booting after
  the notice is posted in `onMessage` would remove the gap.
- **The notice never creates a channel** (Dart owns them, including the
  custom tone); a missing channel means no notice. It alerts through the
  channel's own sound and vibrates by hand, since message channels are
  `playSound: true, enableVibration: false`. An uncached room posts plain
  on `direct_messages` and is replaced when Dart knows better; a known room
  posts as a conversation with its shortcut, so it does not jump sections.
- **A call or invite push gets the notice first**: the invite carries the
  push's event id and replaces it silently; the ring cancels it after the
  tone, since `event_id_only` carries no event type.
- **Fire-and-forget network calls are not error-free**; wrap best-effort
  work in `runBestEffort`.
- **`NotificationCompat.CallStyle` throws on a blank `Person` name**; both
  call builders fall back to a non-empty string.
- **A refinement for a thread the user dismissed is dropped**, never
  re-posted; the thread check is what decides.

## Extension Guidance

- **New transport**: implement `NotificationDeliveryProvider` with
  `retryIfFailed` and `recheckRegistration`, add the enum value, wire
  `notificationDeliveryProviderFor`, `retryFailedDelivery`,
  `recheckDelivery` and `deliveryDependsOnBatteryExemption`.
- **New producer of message notifications**: build a
  `MessageNotificationContent` and call `postMessageNotification`; never
  `showMessage` directly.
- **New headless notification action**: route it through the existing
  dispatcher, give it a distinguishing payload shape, keep it unawaited if
  it must hold the isolate, and wrap it in `runHeadlessMessageAction`'s
  wake lock pattern.
- **Anything needing payload content**: assume `event_id_only`.
- **Anything about server push rules**: add to
  `PushRuleMaintenanceNotifier`, which runs once the rules have synced.

## Dependencies / Integration

- **Calls**: shared sound player, toggles, `zuno_vibration`, and the
  headless action dispatcher; ring presentation in the calls doc.
- **Event display**: `event_display.dart` is the source of truth for a
  notification's text and whether an event is a photo.
- **Security**: the new-sign-in alert reads `client.userDeviceKeys` the
  same way `lib/core/security/` does.
- **Onboarding**: `OnboardingStep.batteryExemption` is queued when
  `needsBatteryExemptionFor` says so, which for UnifiedPush includes the
  distributor's own exemption.
- **Settings**: `notifications_settings_page.dart` for the permission and
  sound toggles; `notification_delivery_page.dart` for mode choice and
  the transport rows, including the distributor battery row;
  `push_target_status_page.dart` for pusher management.
