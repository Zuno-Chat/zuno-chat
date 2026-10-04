# App Foundation

## Overview
Cross-cutting infrastructure the rest of the app sits on: a single
app-wide Matrix `Client`, cold start, connectivity awareness, global
error handling, the android/ios capability layer, the iOS project and its
one Flutter engine, and the Android launch icon/splash. Not a user-facing
feature — every screen depends on this layer.

## Architecture
One `Client` instance for the whole app's lifetime, built by
`createMatrixClient()` (`lib/core/matrix/matrix_client_provider.dart`)
and awaited before `runApp`. There is no repository/service layer:
feature folders (`lib/features/<feature>/presentation/`) hold screens
only, and screens call SDK methods directly (`client.login`,
`room.sendTextEvent`, ...). SDK types (`Client`/`Room`/`Event`/
`Timeline`) *are* the app state — Riverpod providers expose the client
and derived streams, not a separate app-level model. While the app runs it
is also the only Matrix client in the process: push engines and
notification actions open their own short-lived clients only under the
client lease (One Matrix client per process, below). iOS runs one engine
for everything (`EngineHost`, below).

Key providers (`matrix_client_provider.dart`):
- `matrixClientProvider` — the `Client`, overridden in `main.dart` once
  `createMatrixClient()` resolves; throws if read before that. The client
  carries `onSoftLogout: refreshSession`, so an expiring access token is
  refreshed rather than dropped (`authentication.md`).
- `isLoggedInProvider` — `StreamProvider<bool>`, seeded with
  `client.isLogged()` then following `client.onLoginStateChanged`
  (a plain broadcast stream that never replays its current value to a
  new subscriber — without the seed a fresh install would sit in
  `AsyncLoading` forever). Only `loggedOut` reads as signed out:
  `softLoggedOut` is the SDK's state while a token refresh is in flight,
  and treating it as signed out flashed the sign-in screen, popped open
  screens and tore down notification delivery on every refresh.
- `signInInFlightProvider` — `true` while a sign-in call runs
  (`SignInInFlight.during`); `_AuthGate` keeps the signed-out screens up
  meanwhile, since the SDK emits `loggedIn` before its first sync
  (`authentication.md`).
- `firstSyncProvider` — done at once when the client has a sync token (a
  restored session), otherwise on the first `SyncStatus.finished`. It
  watches `isLoggedInProvider`, so every sign-in and sign-out re-arms it.
  Onboarding and the chat list's empty state wait for it, covering what the
  sign-in hold cannot: `client.login` stops waiting for the first sync
  after 10 s.
- `connectionStatusProvider` / `isOfflineProvider` — connectivity
  (`connectivity_provider.dart`), see Communication below.
- `uploadProgressHttpClientProvider` — the `UploadProgressHttpClient`
  wrapping `Client.httpClient`, exposed separately because `Client`
  wraps whatever it's given further in `FixedTimeoutHttpClient`, making
  it impractical to unwrap later.

`Client.httpClient` is
`UploadProgressHttpClient(FreshTokenHttpClient(IOClient(HttpClient)))`.
The SDK refreshes an expiring token only inside its sync loop, so at cold
start anything else racing the first sync (the pusher read, key-backup
lookups) went out with the expired token. `FreshTokenHttpClient` holds any
request carrying the current token until `ensureNotSoftLoggedOut()` (one
shared refresh, a no-op unless the token expires within a minute) and then
swaps in the new token. `/refresh` carries no token, so it never waits on
itself.
The `HttpClient` has a 10 s `connectionTimeout` — connect only, so a
dead route fails fast while a slow upload/download is never cut off.
Responses come gzip-compressed: `HttpClient` advertises gzip and decodes
it itself. zstd was dropped deliberately: on real sync payloads it saved
1–2% over gzip (event IDs, keys and ciphertext don't compress), and the
`zstandard` iOS plugin shipped without its C sources, so it cost a
dependency for nothing. Brotli is out for the same reason.

Navigation has exactly one routing decision: `isLoggedInProvider` +
`_AuthGate` (`lib/app.dart`) switch the root route between the auth
flow (`SignedOutEntry`) and `RoomListPage`; while a sign-in is in flight
(`signInInFlightProvider`) the gate keeps `SignedOutEntry`, although the
SDK already reports logged in. Everything else in the app
is `Navigator.push`. `_AuthGate` also owns the cold-start launch checks
(launch shortcut, notification tap, call launch action or ring, pending
ring, launch share), takes a launch share regardless of login (waiting for
the login state if it is still loading, dropped when logged out) and syncs
notification-delivery transports to login state.

**Look and motion live in `lib/core/ui/`**, and nowhere else. Screens read
`Theme.of(context)`, so these three files restyle the whole app:
- `zuno_theme.dart` — `zunoLightTheme` / `zunoDarkTheme`: a seeded
  `ColorScheme` with the roles that matter pinned, Roboto at weights
  400/500/700 only (older Android has no 600; it snaps to bold), component
  themes, `ZunoRadius`. No elevation or surface tint: depth is the surface
  steps.
- `zuno_colors.dart` — `zunoAmber`, `zunoInk`, avatar tones, and the
  `ZunoColors` theme extension for what Material has no slot for (outgoing
  bubble, success, link). `ZunoColors.of(context)` falls back to the
  brightness default when a test has no Zuno theme.
- `section_label.dart`, `empty_state.dart`, `line_strut.dart`,
  `row_memo.dart` — the shared pieces screens are built from; added only
  when a screen needs one. `RowMemo` returns the identical widget for an
  equal record; the chat list prunes it with `retainOnly`, the chat room
  caps it.
- `card_group.dart`, `card_list_view.dart`, `circle_icon.dart` — the
  grouped-card look of Settings, room info and every page under them: a
  `CardListView` of `CardGroup`s. Hub rows that navigate or act lead with a
  `CircleIcon`; rows inside sub-pages keep a plain icon.
- `step_hero.dart`, `step_layout.dart` — one-question screens (first run,
  recovery, backup, approve this device): `StepHero` is an icon, art or
  photo in a soft circle (112 px, or 72 px `compact` beside fields or
  dense content; with `onTap` it is one labelled button, without it adds
  nothing for a screen reader). `StepLayout` centers hero, title and one
  paragraph over a scrolling middle and pins full-width `actions` at the
  bottom, above the keyboard. When the actions would leave the middle
  under 120 px (landscape, very large fonts) it becomes one scroll view.
  `actionsFollowContent` (approve this device) puts the actions right
  under the text and centers the group; when it does not fit they stay
  pinned and only the text scrolls. Never move buttons into `children`
  for this: they scroll off a small phone.
- `route_settled.dart` — `RouteSettled` mixin: `onRouteSettled()` fires
  once the push slide has finished. Work that would land mid-slide (apply
  a timeline, request members) goes there.
- `zuno_motion.dart` — `ZunoDurations` and `ZunoSlideTransitionsBuilder`,
  registered in the theme for Android only, so every `MaterialPageRoute`
  there slides with no call-site change. Movement only, no fade. iOS keeps
  the Cupertino transition, and with it the edge swipe back, except for
  `ForwardExitPageRoute`'s exit. That route (the onboarding flow) pushes
  with the theme's transition; `ForwardExitPageRoute.popForward` sends it
  out to the leading edge and the route below in from the trailing edge
  (`delegatedTransition`), 250 ms `easeOut` like a pager step, on both
  platforms. Only `popForward` on a settled route exits forward: any other
  pop (sign-out, a call ending), or one while a page above is still
  leaving, is the normal reverse, and a flow that is not on top is removed
  without touching the route above. Reduced motion drops the slide; RTL
  mirrors it.

**Every platform difference is a capability in `lib/core/platform/`.**
`AppPlatform {android, ios}` comes from `Platform.isIOS`, so `flutter test`
runs as android. `PlatformCapabilities` is a const table of required fields returned by
the pure `capabilitiesFor(AppPlatform)`: flags, `videoCodecOrder`, and
`deliveryModes`/`defaultDeliveryMode`. Required fields force a new flag to be decided
for both platforms. Why no build flavors, why `foss` was dropped, and the
capability/seam rules:
[platform-flavors.md](../decisions/platform-flavors.md).
- Call sites never read `Platform.isIOS`; only `app_platform.dart` does.
  Consumers watch `platformCapabilitiesProvider` where a `Ref` is
  reachable, else take a `PlatformCapabilities` parameter that defaults to
  `ambientCapabilities`.
- `ambientCapabilities` is a getter plus a `@visibleForTesting` setter.
  Production never assigns it; a test sets it to run a flow as iOS end to
  end.
- Where iOS reimplements rather than skips, the difference is an
  interface: the call seams in `lib/core/calls/platform/`
  (`IncomingCallPresenter`, `OngoingCallPresenter`, `RingbackTonePlayer`,
  `SystemCall`, `CallAudioOutput`, `PushRingBridge`), each built by a
  `*For(capabilities)` factory. The per-platform table is in `calls.md`.

Each flag is one of these kinds:

| Kind | Flags | Values |
|---|---|---|
| Native handler, both platforms | `nativeVideoTools`, `nativeImageResize`, `nativeSignOutWipe`, `sensitiveClipboard`, `screenSecurity`, `uploadForegroundService`, `networkAvailabilityEvents`, `headlessWakeLocks`, `nativeRoomOpens` (`zuno/shortcuts` room opens; pinning stays on `homeScreenShortcuts`), `clientLease`, `inboundShare` | `true` on both |
| Awaiting an iOS equivalent | every other Android-`true` flag, e.g. `pictureInPicture`, `notificationImages` (off, the poster fetches no thumbnail), `notificationAvatars` (iOS shows no sender avatar without communication notifications, so it fetches none) | iOS flips to `true` once a native handler exists |
| Permanent: Android concept | `batteryExemption`, `backgroundDataRestriction`, `autostartSettings`, `lockScreenCallUi`, `foregroundSyncService`, `vibrationPatterns`, `keyboardLearningOptOut`, `fullScreenIntent`, `homeScreenShortcuts` (pinning; iOS quick actions would be a new flag) | iOS stays `false` |
| Android-only behavior | `atomicDatabaseBatches` (one database connection shared by every engine), `instantPushNotices` (a native notice posted from the push; on iOS the APNs alert is the system's) | `true` on Android only |
| Permanent: seam selector | `nativeIncomingRingUi`, `callForegroundService`, `nativeRingbackTone` (Android); `callKit` (iOS) | `true` on their own platform only; the call factories check `callKit` first (`calls.md`), so the Android three are never flipped |
| iOS-only behavior | `apnsRegistration`, `playerNeedsMediaType`, `callMuteByInputMixer`, `signOutWipeKeepsProcess`, `videoRendererNeedsDetach` (`calls.md`) | `true` on iOS only |
| iOS push stack | `voipRing` (the PushKit ring, `calls.md`), `nseNotifications` (the notification service extension, `notifications.md`), `nativeNotificationActions` (Reply and Mark as read queued natively); each gates its `zuno/*` channels (below) | `true` on iOS only |
| Both platforms | `pushDiagnostics` (the Diagnostics hub, `settings.md`) | `true` on both |
| Apple limitation | `recorderWritesOgg` (Apple can't write Ogg), `videoCodecOrder` (`null` on iOS, see `calls.md`), `locationServicesSettings` (no link into Location Services), `filesTypedByExtension` (other apps type a file by its name), `screenshotBlocking` (no app can block a screenshot; picks the screen-privacy copy) | differs on iOS for good |

### iOS project

| Path | Holds |
|---|---|
| `ios/Runner/` | The app target: plugins, `Runner.entitlements`, `PrivacyInfo.xcprivacy`, bundled sounds (`message_tone.caf`, `silent_ring.caf`, `fallback_ring.caf`) |
| `ios/ShareExtension/` | The share extension target (`im.zuno.chat.ShareExtension`, `chats-messaging.md`): own Info.plist, entitlements, privacy manifest, and an xcconfig taking its version from Flutter's build name and number, since an extension's version must match its app's |
| `ios/NotificationService/` | The notification service extension (`im.zuno.chat.NotificationService`, `notifications.md`): own Info.plist, entitlements (notify group, Time Sensitive), privacy manifest, the same version xcconfig, and a bridging header for the Megolm ABI |
| `ios/Shared/` | Swift compiled into the app and the share extension (`ShareInbox.swift`) |
| `ios/NotifyShared/` | Swift compiled into the app and the notification extension: read model, sealed files, Keychain items, the extension's pipeline, ring decisions, `VoipBlob`, `CallIdentity` |
| `ios/RunnerTests/` | XCTests against `@testable import Runner`, which compiles both shared folders |

- **App Group** `group.im.zuno.chat.$(DEVELOPMENT_TEAM)`, from the
  project-level `ZUNO_APP_GROUP`, in Runner's and the share extension's
  entitlements. It is team-scoped because a group registered on the
  Personal Team may stay stuck there. Code never spells it: it reads
  `ZunoAppGroup` from its own Info.plist.
- **Notify App Group** `group.im.zuno.chat.notify.$(DEVELOPMENT_TEAM)`
  (`ZUNO_NOTIFY_GROUP`, read from `ZunoNotifyGroup`), in Runner and the
  notification extension only, never the share extension. It holds the read
  model (`Library/Application Support/zuno-nse/`, protection
  `completeUntilFirstUserAuthentication`) and doubles as the access group of
  the notify Keychain item.
- **Keychain items** besides the database key, all
  `AfterFirstUnlockThisDeviceOnly` and never synchronized:

  | Service | Access | Holds |
  |---|---|---|
  | `im.zuno.chat.notify` | Notify group | `rm_key`, `install_key`, the extension's credential |
  | `im.zuno.chat.voip` | Runner only | The VoIP key and its predecessor |
  | `im.zuno.chat.unlock-probe` | Runner only | One byte that reads only after first unlock |

- **A reinstall starts with fresh notify and VoIP items** (`NotifySweep`):
  Keychain items outlive an uninstall, so the first launch without the
  `Library/zuno-install-v1` marker deletes both, never the database key.
- **Privacy manifests**: Runner declares UserDefaults (`CA92.1`, and
  `1C8F.1` for the notify group's suite) and file timestamps (`C617.1`); the
  share extension file timestamps only; the notification extension
  UserDefaults (`1C8F.1`).

Runner's Info.plist keys beyond usage descriptions and background modes:

| Key | Why |
|---|---|
| `CFBundleURLTypes` | The `im.zuno.chat` scheme, which the share extension opens |
| `FlutterDeepLinkingEnabled` `false` | Flutter would otherwise turn an opened URL into a route. Plugins claim URLs through `addSceneDelegate` (UIScene delivers them to `scene(_:openURLContexts:)`); an unclaimed one is ignored |
| `ITSAppUsesNonExemptEncryption` `false` | Skips the export-compliance question per upload; holds only while France is unselected in App Store Connect (`docs/plan-ios-native.md`) |
| `SRResearchDataGeneration` `false` | SensorKit research apps may not collect speech metrics during Zuno's CallKit calls |
| `ZunoAppGroup`, `ZunoNotifyGroup` | `$(ZUNO_APP_GROUP)`, `$(ZUNO_NOTIFY_GROUP)`, for code |

There are no storyboard keys (`UIMainStoryboardFile`,
`UISceneStoryboardFile`): `Main.storyboard`'s `FlutterViewController` would
create the implicit engine (below).

### One Flutter engine on iOS (`EngineHost`)

**iOS runs one app-owned engine** (`EngineHost.swift`), not Flutter's
implicit one. Why: the implicit engine needs a scene, which a ring or a
notification action in the background lacks, and two engines cannot share
a `Client` or WebRTC objects.
- `SceneDelegate` builds its window around it. A VoIP ring
  (`startForRing`) or a notification action (`start(.action)`) starts it
  headless, with `--zuno-wake=ring|action` (read back over `zuno/launch`)
  and the lifecycle set to `paused`; a scene that connects later gets the
  same engine. The full `main()` runs either way, so a ring or an action
  uses the app's own client, lease and call stack.
- **It never starts an engine before first unlock** (`ProtectedData`: the
  VoIP Keychain item, else `isProtectedDataAvailable`): the database key
  and the app's files are unreadable until then. A scene shows the launch
  screen and gets the Flutter view once protected data arrives; a ring
  stays native (`calls.md`).
- **Plugins register once, in `EngineHost.registerPlugins`**: the generated
  registrant, then the Zuno plugins. Never call the AppDelegate's
  `registrar(forPlugin:)`, `hasPlugin` or `valuePublishedByPlugin`: they
  silently start Flutter's `LaunchEngine`, a second engine.

**The iOS push channels**, each behind its flag (wrappers no-op while it
is off and catch `MissingPluginException`, so Android never calls them):

| Channel | Flag | Methods |
|---|---|---|
| `zuno/apns` | `apnsRegistration` | `getToken`, `environment`, `removeDelivered` |
| `zuno/push_diag` | `pushDiagnostics` | `snapshot`. iOS: notification settings, environment, ledger, read-model age, extension log, `app.log` (ring outcomes), MetricKit summaries. Android: a flat map (permission, channels, battery, standby), failed reads omitted |
| `zuno/voip` | `voipRing` | `status`, `rotateKey`, `ackKey`, `takeEvents`, `setSession`; `devExport` only in the development APNs environment |
| `zuno/launch` | `voipRing` | `takeWakeReason`, `takeDiagnostics` (MetricKit lines) |
| `zuno/nse` | `voipRing`; `nseNotifications` for the second half | `threadKey`, `writeMeta`, `writeRoom`, `deleteRoom`, `wipe`; `writeShown`, `takeMarks`, `readOutcomes`, `setCredential`, `syncBadge` |
| `zuno/notification_actions` | `nativeNotificationActions` | `takeActions`, `finish`; native → Dart `actionsAvailable` |
| `zuno/wake_lock` | `headlessWakeLocks` | `acquire`, `release` by tag: a background task each on iOS, also held around sends (`notifications.md`) |

### One Matrix client per process

**At most one Matrix client is live per process, and the app's always
wins** (`zuno/client_lease`, `client_lease.dart`). matrix SDK 12.0.1 writes
`olm_account` and each identity key's Olm session map as whole values from
the client's own box cache, so two live clients on one store silently lose
each other's crypto writes (one-time keys, Olm sessions).

| Holder | Rule |
|---|---|
| App, `createMatrixClient()` | Takes the app lease before opening the store and keeps it for the process. A background holder is asked to `yield`; after 5 s the app is force-granted (logged), the one case where two clients overlap. With no native answer Dart goes on after 7 s |
| Background, `createMatrixClient(backgroundSync: false)` | Denied while the app holds the lease. Otherwise it waits up to 8 s behind another background holder, which is asked to yield; one request per isolate at a time. `ZunoClient.dispose` releases it; a detached engine's leases are released and its waiters denied |

What each background path does on `ClientLeaseDenied`:

| Path | Then |
|---|---|
| Push | Dropped; the instant notice stays (`notifications.md`) |
| Push engine's ring hold, sending a decline | Hands it to the app's decline route (`calls.md`) |
| Notification action or Decline in the action engine (Android) | Retries the hand-off to the app's live route for about 6 s |
| FCM token move in a push engine | Saved as the pending token |

- Native halves: Android `ClientLeases` over the pure, JUnit-tested
  `ClientLeaseBook` in `zuno_notifications`, on every engine that plugin
  reaches; iOS `ClientLeasePlugin` over `ClientLeaseLedger` (XCTests), on
  `EngineHost`'s one engine. Without the native half
  (`MissingPluginException`) both kinds go on unleased.
- **Background clients never clear the store** (`ZunoClient(appClient:
  false)`): the SDK's own `clear()` on a failed init or refresh would
  otherwise wipe the shared database from a push engine.
- Cost: a background push or action is denied while the app holds the
  client; the native notice or the hand-off covers it.

## Data & State
The SDK's local database (SQLCipher-encrypted `sqflite`) is the
persistence layer — everything the SDK tracks (access token, Olm
account, Megolm sessions, cached room/event state) lives in one file,
`zuno.db`, opened in `createMatrixClient()` via `_openDatabase()`. No
app-level database or cache sits alongside it. `client.init()` restores
any prior session from that database and, if logged in, starts the sync
loop. Push engines and notification actions open the same file from their
own engines in the same process, one client at a time.

The database is always opened with its key; there is no plaintext
upgrade path, so a plaintext `zuno.db` fails to open rather than being
read unencrypted. `PRAGMA cipher_version` is checked explicitly after
opening (`_assertSqlCipherPresent`) because `PRAGMA key` fails silently
on stock sqlite3 with no other signal.

**Only the app mints a database key.** A `zuno.db` whose key is gone can
never be opened, so the app's `obtainDatabaseCipher(databasePath:)` deletes
it before generating a new key, and the device starts signed out instead of
failing at launch. The likely cause is an iOS backup restored on another
phone: the key is `first_unlock_this_device` and never travels. Only a
genuinely absent key triggers it; an unreadable one (a locked Keychain)
throws `DatabaseKeyUnavailable` first. It also deletes the `-wal`, `-shm`
and `-journal` files itself: sqflite_sqlcipher's delete removes only the
main file on iOS. A background client passes `createIfMissing: false` and
throws `DatabaseKeyUnavailable` instead, so it can never replace the app's
store. On iOS the Keychain key survives sign-out by design (the iOS wipe
keeps the open database, Gotchas) and survives uninstall; a reinstall
reuses it for a fresh database.

**Nothing discards the key on a read error.** On Android
`SecureSecretStore` sets `resetOnError: false`: flutter_secure_storage's
default deletes every stored secret after one Keystore read error, which
would lose the key and make the next open delete the database. Only Start
over uses the discarding variant (`SecureSecretStore.discardingUnreadable`).

**SQLCipher's derived key is cached** (`database_raw_key.dart`) as a raw-key
literal tagged with the file's 16-byte salt (`<salt hex>:x'<key hex>'`,
secure storage key `matrix_database_raw_key`). The passphrase is already 256
random bits, so SQLCipher's 256,000 PBKDF2-HMAC-SHA512 rounds per cold
process buy nothing.
- An open with the cache needs a matching salt and a read-only probe that
  reads the keyed tables. Any failure forgets the cache and opens with the
  passphrase; the file is never touched.
- Only the app derives it, unawaited after its store opens: vodozemac's
  native `CryptoUtils.pbkdf2` in an isolate, falling back to the pure-Dart
  PBKDF2 kept as the vector-tested reference. A wrong result fails the probe
  and is never cached; the native path is covered by that runtime probe,
  not by unit tests.
- Minting or discarding the database key forgets it. It is shared Dart, so
  iOS has it too.

**On Android every SDK write transaction is one native batch**
(`AtomicBatchDatabase`, `atomicDatabaseBatches`). Android's sqflite_sqlcipher
keeps one native connection per path in a process-wide registry, shared by
every engine. A Dart-side transaction spans channel round trips, so an
engine that dies inside one leaves the shared connection mid-transaction,
and every later write in the process, Olm and Megolm state included, is
silently discarded. The wrapper replays each `Batch.commit` as
`BEGIN IMMEDIATE … COMMIT` in one native call, rolls back on failure,
refuses `continueOnError`, and serializes every call. iOS registers its
connections per engine, so it stays unwrapped. Residual: a batch failing
after `BEGIN` needs a second `ROLLBACK` call, and another engine's write in
that round trip can be rolled back with it. The trigger is disk full, an I/O
error or corruption; owning a fork of the crypto database plugin was judged
the bigger risk.

**Opening the shared store** (`shared_database_open.dart`): a keyed open
that meets another engine's transaction on the Android connection fails with
a `TypeError` (sqflite casts the keyed open's options while handling
`recoveredInTransaction`). The open retries, 10 ms doubling to 250 ms, for
1 s, then treats the transaction as abandoned. Only for a file whose header
says encrypted, it reopens without the key with
`rollbackActiveTransactionOnOpen`, which returns the shared keyed connection
rolled back. It never deletes the store: it deletes a file only when its
header proves it plaintext after that reopen, closes a connection that
cannot read the keyed tables, and leaves an unreadable file as it is.

App data stays out of device backups. Android sets `allowBackup="false"`.
iOS flags Application Support (database, notification avatars) and
Documents `isExcludedFromBackup` at every launch in `AppDelegate`; the flag
on a directory covers files created later. The share inbox in the App Group
and the notify group's `zuno-nse` folder are flagged when created.
`Library/Preferences` still backs up (cfprefsd rewrites the plist, so a
flag would not stick): a restore brings back the signed-in marker without a
database, so the sign-out wipe clears it on first launch.

## Communication
**Cold start.** `main()`'s independent setup steps (notifications,
building the Matrix client, reading stored preferences) run in
parallel, not sequentially — none depends on the others. Inside
`createMatrixClient()`, after the app lease, vodozemac (E2EE) init and
opening the local database likewise run concurrently, joined with an
explicit `await` only where crypto actually needs it. A start that throws
is retried, then asked about (Key Design Decisions). `client.init()` is called with
`waitForFirstSync: false`: the SDK's default (`true`) blocks return
until a live `/sync` round trip completes, holding up `runApp` on every
cold start even though everything needed to render the room list
(rooms, account data, device keys) is already restored from the local
database moments earlier by `waitUntilLoadCompletedLoaded` (left at its
default `true` — that part is local disk I/O, not network). The sync
loop still starts regardless; `waitForFirstSync: false` only stops
*awaiting* the round trip. `RoomListPage`'s `StreamBuilder` on
`client.onSync.stream` repaints once that first sync actually lands, so
nothing else needed to change for it to keep working.

**Connectivity.** `connectionStatusProvider` exposes a three-state
`ConnectionStatus` (`online` / `noInternet` / `unreachable`) from a
pure, fake-async-tested `ConnectionMonitor` (`connection_monitor.dart`)
fed by two signals. `isOfflineProvider` is derived: anything but
`online`.

| Signal | Source | Drives |
|---|---|---|
| Device network | EventChannel `zuno/network`: `NetworkAvailabilityStreamHandler.kt` (Android default-network callback), `NetworkPlugin.swift` (`NWPathMonitor`, any status but `unsatisfied` is available) | `noInternet`, after the network stays gone 2 s |
| Homeserver | `client.onSyncStatus` + probe `GET /_matrix/client/versions` (8 s timeout, <500 = reachable) | `unreachable` |

- A sync connection failure (`SyncConnectionException` or
  `TimeoutException`) is never trusted alone: it triggers one probe, and
  only a failed probe reports `unreachable`. A stray error from
  `forceSyncNow` (which aborts a long-poll without cancelling its HTTP
  request) or a network handoff is contradicted by the probe.
- While not online, reprobes back off 2 s → 10 s cap; only in the
  foreground (`AppLifecycleListener`), and returning to the foreground
  probes at once.
- Any `finished` sync or `MatrixException` response clears to `online`
  immediately, cancelling pending probes (a late failed probe is
  ignored via a generation counter).
- Network coming back does not clear `noInternet` by itself — a probe
  must confirm the homeserver answers.
- A sync succeeding while the network is reported gone clears
  `noInternet` only if that sync *started* after the loss; one already
  in flight when the network dropped proves nothing.
- `DefaultNetworkTracker.kt` ignores `onLost` for a network already
  replaced as default, so a wifi→cellular handoff never reports a loss.

`client.syncErrorTimeoutSec` is `1` (SDK default 3) so the retry
cadence doesn't add lag to noticing recovery.
`FixedTimeoutHttpClient.defaultNetworkRequestTimeout` is left alone:
shortening it would cut off real slow transfers.

**Backgrounding pauses `/sync`, except during a call or a ring.**
`_AuthGate.didChangeAppLifecycleState` (`lib/app.dart`) calls
`client.abortSync()` on `paused` and sets `client.backgroundSync = true`
on `resumed`, via the pure predicates
`shouldPauseBackgroundSync`/`shouldResumeBackgroundSync`
(`background_sync_lifecycle.dart`) — both skip this entirely when
`NotificationDeliveryMode.backgroundService` is active, since that mode's
whole purpose is keeping `/sync` alive while backgrounded. The pause
predicate also takes `inCall` (a call in `activeCallProvider` or a ring in
`SystemRing`) and never pauses then, since a call learns of the other side
leaving, and a ring of an answer elsewhere, only through sync; when the
call, or on Android the ring, clears while still `paused`, `_AuthGate`
aborts sync at that point. A CallKit answer on the lock screen never
resumes the app, so on iOS a ring or call starting in the background
turns sync back on. `abortSync`
rather than merely dropping `backgroundSync` is deliberate: it also tears
down the in-flight long-poll immediately (see the `abortSync` gotcha
below), rather than letting it run to its next natural timeout.

The connectivity banner (`_ConnectivityBanner`, `lib/app.dart`) says
"no internet" only for `noInternet` and a separate cannot-connect
message for `unreachable`, so a homeserver outage never blames the
user's network. It is
pinned above the `Navigator` via `MaterialApp.builder`, so it shows
regardless of which screen, dialog, or full-screen route (`CallPage`)
is on top, and has no dismiss button — it stays up for exactly as long
as the underlying problem does. This app's own core Matrix traffic
(sync, sending) is left ungated while offline — the SDK already queues
and retries it, and blocking it would be a regression. What's gated
instead is non-essential, doomed-while-offline work: link-preview image
fetches, room history requests and starting a new call.

## Key Design Decisions
- **Single `Client`, no repository layer** — SDK types are the app
  state; screens call SDK methods directly. Keeps one source of truth
  and avoids a parallel app-level model drifting from the SDK's own.
- **A failed start asks before deleting anything.** The SDK clears the
  whole store on an unexpected `Client.init` error; `ZunoClient` skips that
  clear during session restore (sign-in and registration still clear).
  `createMatrixClient` tries three times (250 ms, then 1 s apart), then
  `StartupFailurePage` (`lib/features/startup/`) says nothing was deleted
  and offers Try again, or a confirmed "Start over on this device", which
  discards the key and the database and starts signed out. Each failed round
  is reported like a zone error. Why: a full disk or a flaky Keystore must
  not cost someone their encryption keys (`docs/brand-voice.md`:
  protective), and a client that cannot start gets a screen instead of an
  endless splash. A stored session needs no network to init, so an offline
  launch never fails the start.
- **`waitForFirstSync: false`** — cold start must not block on a live
  network round trip when the local database already has everything
  needed to render; see Communication above.
- **Parallel, not sequential, setup** — independent init steps (in
  `main()` and inside `createMatrixClient()`) run concurrently since
  none depends on the others; sequential-by-default was a real,
  measured cold-start cost with no correctness benefit.
- **Device network and homeserver reachability are separate signals** —
  the sync stream alone can't tell "your internet is down" from "the
  server is down", and the banner must not blame the wrong one. The
  device signal is a native default-network callback, not a plugin.
- **A sync failure is confirmed by a probe, not an error count** — a
  stray error from `forceSyncNow` or a handoff is disproved by one
  cheap request instead of waiting for a second failure.
- **`isLoggedInProvider` is the only routing decision** — `_AuthGate`
  swaps the root route's content; everything else pushed on top
  (Settings, room screens) is unaffected by login/logout by default,
  which is why logout needs its own explicit handling (see Gotchas).
- **`/sync` pauses while backgrounded, except under the background-service
  delivery mode** — keeping a long-poll open with no screen on wastes
  battery for no benefit under the other two delivery modes (push carries
  the wake-up instead); the background service's whole reason to exist is
  the opposite, so it's exempted rather than fighting itself.
- **Attachment sends survive backgrounding on their own**: `abortSync`
  leaves the HTTP client alone, and an in-flight send holds a dataSync
  foreground service (`UploadForegroundService`, see chats-messaging.md)
  so the cached-app freezer doesn't stall it. iOS holds a background task
  instead (`UploadServicePlugin.swift`), about 30 s: a longer upload is
  still suspended and shows as not sent.
- **Boot splash matches the Android launch theme exactly** —
  `ZunoBootSplash` (painted at the very first `runApp`, before
  `createMatrixClient()` has even started) and the `loading:` branch of
  `_AuthGate` both render the same `ZunoSplash` widget
  (`lib/core/ui/zuno_splash.dart`), deliberately
  matched pixel-for-pixel (color, mark size) to the OS-drawn
  `LaunchTheme` window background underneath — a cold start paints the
  mark twice, from two independent layers (OS, then Flutter's first
  frame), and any visible mismatch between them reads as two separate
  loading screens rather than one continuous one. iOS matches it the same
  way: `LaunchScreen.storyboard` is amber with `LaunchImage` (the ink mark)
  pinned at 96 pt. The app icon is one 1024 px image per appearance
  (default, dark, tinted) from `assets/logo/ios-icon-1024*.svg`, opaque, as
  App Store validation requires.

### Launch targets hold the splash, then land without a transition

On the first build that is logged in with no sign-in in flight, `_AuthGate`
holds the splash and runs every launch check concurrently once
(`_handleLaunch`); the root swaps to
`RoomListPage` only after they finish, capped at 2 s. A launch route
pushed by a check is already on top at the swap, so the room list is
never painted alone. Launch pushes use `LaunchRoute`
(`lib/core/navigation/launch_route.dart`: zero forward transition, normal
reverse) and the call router takes `instant: true` for the same reason.
Cost: a plain cold start shows the splash for as long as the checks take,
about a second on a cold process (the active-ring notification query
dominates). Gating on the fast reads only would bring the flash back for
the ring case, so it was not done.

**A launch target is taken once.** Android hands a relaunch from Recents
(`FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY`) and a restored activity the original
launch intent again. `MainActivity.onCreate` swaps such an intent for a bare
`ACTION_MAIN` before `super.onCreate` attaches the plugins
(`LaunchIntentDecision`, JUnit-tested), so its share, room or notification
tap never repeats. A share or room open that arrives before anyone listens
is held, the latest only: on iOS natively until the newest engine takes its
launch value (`LaunchHandoff`), and in Dart for the first listener
(`HeldBroadcast`).

## Gotchas & Constraints
- **Two ambers.** Brand amber as text on the paper surface is 2:1.
  `primary` is a darker amber for text, icons and lines;
  `primaryContainer` is brand amber as a *fill* with an ink label. For a
  soft tint use `secondaryContainer`: `FilledButton.tonal` shares
  `FilledButtonTheme` with `FilledButton`, so a tonal button on a
  `primaryContainer` surface disappears. `zuno_theme_test.dart` fails any
  text role under 4.5:1 on any surface step.
- **A theme edit changes screens its diff never touches.** Sweep call
  sites that override only part of a themed component. Known cases: a
  local `InputDecoration.border` is the *last* fallback, so the themed
  `enabledBorder`/`focusedBorder`/`disabledBorder` win (the theme sets
  every state, as `UnderlineInputBorder` so labels float inside the fill;
  a field with its own container, like the composer, opts out with
  `filled: false` and `InputBorder.none` on each); a themed
  `appBarTheme.titleTextStyle` would stop following a local
  `foregroundColor` (the media viewers are white on black), so it is left
  unset; `ListTile` keeps a themed style's own color, so the subtitle style
  pins `onSurfaceVariant`; `dividerTheme.space` stays unset because
  `const Divider()` sites rely on the 16 px default.
- **A `ListView` with its own `padding` stops handling the system
  insets.** With `padding: null` it pads itself by `MediaQuery.padding`
  and hides that padding from its children. With explicit padding it does
  neither: the last row sits under the navigation bar, and a nested
  shrink-wrapped `GridView`/`ListView` adds the inset as its own padding
  (a 48 px hole mid-page). `CardListView` does both jobs; a nested
  scrollable elsewhere takes `padding: EdgeInsets.zero`.
- **Filled fields and dialogs.** Stacked filled fields need a gap or they
  merge into one block. A dialog with more than one field is
  `scrollable: true`, or it overflows above the keyboard on a small phone.
  Actions that may not share a row set `actionsOverflowDirection:
  VerticalDirection.up`, so the stack reads action first, Cancel last.
- **One layout matrix for every new layout**: `test/helpers/
  layout_matrix.dart` (`expectSurvivesLayoutMatrix`) pumps a small phone,
  the smallest phone at 2x text, landscape and right-to-left, with system
  insets. It only catches thrown errors, so pass `afterEach` to assert
  what must stay visible (content clipped inside a scroll view throws
  nothing).
- **The test font is 1 em per glyph**, about twice Roboto's width, so a
  does-it-fit assertion means nothing with it. `test/helpers/
  real_fonts.dart` (`loadRealRoboto`) loads Roboto from the Flutter cache.
- **A pushed page's route animation reports `completed` at first build.**
  It only starts running after that frame, so `RouteSettled` looks at it
  in the first post-frame callback.
- **The push curve must start gently.** A push spends its first ~100 ms
  building the new screen, and what the curve covers in that window is
  never seen. `fastOutSlowIn` covers 46% by then; a decelerate curve covers
  89% and reads as a stutter. `zuno_motion_test.dart` pins it.
- **A `delegatedTransition` reaches only a route below whose result type it
  matches** (`nextRoute is ModalRoute<T>` in Flutter's `didPopNext`).
  `ForwardExitPageRoute` is `<Never>`, which matches every type, so its
  forward exit also slides over a typed route.
- **Silent framework errors skip the debug SnackBar**
  (`FlutterErrorDetails.silent`, e.g. an image load that fails after its
  widget is gone); they still reach the previous handler.
- **Riverpod 3 retries a failed provider on its own.** A `FutureProvider`
  whose error must reach the UI (the pinned-homeserver connection is the
  first) has to pass `retry: (_, _) => null`; otherwise it keeps retrying
  with backoff and the screen stays in `AsyncLoading` forever.
- **A logged-in `ZunoApp` widget test must mock `zuno/shortcuts` and
  `zuno/share`.** An unmocked channel never answers inside fake-async
  pumps, so `_handleLaunch` never completes and the splash never yields
  to the room list. `test/app_launch_target_test.dart` is the harness.
- **Logging out doesn't by itself change what's on screen.**
  `_AuthGate` only swaps the *root* route's content; anything pushed on
  top (e.g. Settings, where "Sign out" lives) stays on screen unless
  explicitly popped. `isLoggedInProvider` seeds with `client.isLogged()`
  then follows `onLoginStateChanged`, which also fires for a remote
  "sign out everywhere else" — so the pop-to-root behavior
  (`shouldReturnToRootRoute` / `root_route_reset.dart`) is driven from
  that single stream in `_AuthGate`, not from individual sign-out
  buttons, to cover every way of becoming logged out with one rule. It
  requires a real logged-in → logged-out *transition*, not plain
  `!loggedIn`, since a cold start also emits `false` and the user may be
  mid-flow on a pushed sign-in screen.
- **Every sign-out ends in a full app-data wipe** (`sign_out_wipe.dart`).
  A `_AuthGate` listener (`fireImmediately`) hands each login state to
  `SignOutWipe`: signed in sets `session.signed_in`; signed out with that
  marker stops push delivery (5 s budget), then calls
  `ActivityManager.clearApplicationUserData` over `zuno/app_data`. Android
  kills the process and drops files, prefs, keys, notifications, channels,
  shortcuts and runtime permissions; the next launch is a fresh install.
  The marker is what separates a sign-out from a device that never signed
  in, and it catches a sign-out noticed elsewhere (remote) at the next
  launch; push engines never sign out on their own, since background
  clients never clear the store. Sign-out paths therefore clean nothing
  local themselves. The native reply must be `true`: anything else counts
  as refused and keeps the marker, so the next launch retries. A wipe that
  leaves the process running clears the marker and releases the latch, so a
  later sign-in and sign-out run again.
- **The iOS wipe keeps the process, so it keeps the open database**
  (`signOutWipeKeepsProcess`). iOS apps can't quit themselves, and deleting
  the live SQLCipher file or its Keychain key would strand a same-session
  sign-in: its data would go to a deleted file, and the next launch would
  sign out and lose its keys. The SDK has already emptied the database
  (`clear()` runs before `loggedOut`), so Dart `VACUUM`s it (deleted rows
  leave free pages behind), then passes its exact path as `keep`.
  `AppDataPlugin.swift` refuses without one, then empties Application
  Support (bar that file and its sidecars), Documents, Caches (decrypted
  media), tmp (picker originals), the App Group share inbox, the
  app-switcher snapshots and the prefs domain, skipping iOS's own
  `com.apple.*` items. Dart then reloads
  `SharedPreferences`, whose in-memory cache would otherwise keep the old
  values. The push teardown that runs first empties `zuno-nse` (bar its
  signed-out marker) and deletes the notify and VoIP Keychain items
  (`notifications.md`). A same-session sign-in must start clean too:
  `onboardingStoreProvider` and `securityPromptStoreProvider` watch
  `isLoggedInProvider`, so their in-memory mirrors last one session, and
  `_AuthGate` invalidates `homeserverProvider` on sign-out, since `clear()`
  nulls `client.homeserver` (`authentication.md`). A new provider that
  keeps session state in memory watches `isLoggedInProvider` the same way.
- **`_AuthGate`'s `ref.listenManual` subscriptions must not become
  `build()`-driven.** `_AuthGate` sits at the bottom of the navigation
  stack, and Flutter defers rebuilding a dirty element under a covered
  route. Delivery-mode changes (Settings → Notifications → Delivery) and
  notification-permission changes in system settings both happen with
  routes stacked over this one, so a `ref.watch` in `build()` would not
  run `_syncNotificationDelivery` at the moment of the change. Observing
  the providers directly is what makes the sync fire regardless of
  what is on top.
- **`vod.init()` (vodozemac) throws on a second call within the same
  isolate** — it does not no-op. `createMatrixClient()` always calls
  `ensureVodozemacInitialized()` (never a bare `vod.init()`), which
  matters because push engines and the notification-action isolate call
  `createMatrixClient()` more than once.
- **The SDK's `BoxCollection.transaction` has no `try/finally`** (matrix
  12.0.1, upstream): an action that throws leaves `_activeBatch` set, so
  later direct writes land in a batch nobody commits until the next
  transaction replaces it, while the box cache already shows them.
- **The User-Agent is per isolate and per client.** `installUserAgent()`
  (`lib/core/network/user_agent.dart`) sets `HttpOverrides.global`, so
  every dart:io client created afterwards sends
  `Zuno/<version> (Android; im.zuno.chat)`, or `(iOS; …)` from
  `currentAppPlatform` — Matrix SDK, modules, images,
  tiles. It runs first in `_runApp` (covering `--unifiedpush-bg` and
  `--fcm-bg`) and in the notification-action isolate's client builder; a new
  isolate entry point must call it before anything builds an HTTP client,
  or its traffic goes out as `Dart/x.y`. The version comes from
  `PackageInfo`; unreadable, the agent drops it rather than failing.
  Sentry sends its own agent. The MapTiler key is restricted to the
  `im.zuno.chat` substring, so tiles depend on this.
- **`Client.importantStateEvents` must list any state type a feature
  needs live, synchronously-applied updates for.** The SDK only updates
  `room.states` for a live incoming state event when the room is fully
  loaded (`!room.partial`) or the event type is in
  `importantStateEvents` — otherwise the update is silently dropped
  until something calls `room.postLoad()` (never called in this app).
  `m.call.member` is added for this reason; a similarly-omitted type
  would fail the same way, silently.
- **Nothing in a widget test syncs.** `RoomPage`, `RoomListPage` and
  `CallPage` render in widget tests from seeded in-memory state
  (`test/helpers/fake_matrix.dart`, fake call sessions), but sync and
  pagination against a server stay uncovered. `buildTestClient` has no sync
  token, so a test reaching `firstSyncProvider` (onboarding steps, an empty
  `RoomListPage`) overrides it. Logic that can be pulled out as a pure
  function is tested directly (`shouldReturnToRootRoute`, `becameOnline`,
  `shouldPauseBackgroundSync`/`shouldResumeBackgroundSync`).
- **`SnackBar.persist` defaults to `true` whenever an `action` is set**
  — a `persist`-true SnackBar ignores `duration` entirely. The global
  error SnackBar always carries a Copy action, so it needs an explicit
  `persist: false` or it never auto-dismisses.
- **Showing a SnackBar (or mutating a Riverpod provider) synchronously
  from inside `FlutterError.onError`/`dispose()` can itself throw** —
  both can run while Flutter's build pipeline is still finalizing
  (e.g. `dispose()` during `BuildOwner.finalizeTree()` on a Navigator
  transition), and both Riverpod's `_debugCanModifyProviders` check and
  Flutter's own "Build scheduled during frame" assertion fire on any
  state change made from there. `global_error_handler.dart`'s
  `showErrorSnackBar` and any provider mutation triggered from a
  `dispose()` must defer via `scheduleMicrotask` (not
  `addPostFrameCallback`, which only fires if another frame is actually
  scheduled) — this is a durable, general risk for anything this
  handler ever reports, not tied to one bug.
- **`project.pbxproj` changes go through CocoaPods' own xcodeproj gem**
  (`GEM_HOME=/opt/homebrew/Cellar/cocoapods/1.17.0/libexec`; files go in
  with `tool/xcode/add_sources.rb <target> <path>…`), which keeps
  `objectVersion` at 60. Xcode 27 writes 110 for new projects, CocoaPods
  cannot read it, and `pod install` then fails. Keep "Embed Foundation
  Extensions" above "Run Script" in Runner, or the build reports a cycle
  through Thin Binary, and keep extensions out of the Podfile.
- **Adaptive icon safe zone is a circle, not a square** — a square mark
  must be sized to its diagonal (`safe-zone-diameter / sqrt(2)`) to
  clear a circular/squircle mask, not to the safe-zone figure as drawn.
- **`values-night` outranks `values-v31`** — a dark-mode-specific splash
  override needs `values-night-v31/`, not just `values-v31/`; Android
  ranks the night-mode qualifier above the platform-version one.
- **Notification small icons are alpha-mask silhouettes on API 21+** —
  RGB is discarded and the shape is tinted by the system, so a
  full-color launcher icon renders as an unrecognizable blob; a
  dedicated single-color drawable is required.
- **`oneShotSync` joins an in-flight sync rather than starting one.**
  `Client._sync` is `_currentSync ??= _innerSync(timeout: timeout)` — with
  a sync already in flight (the SDK's own long-poll loop reopens one
  continuously under `backgroundSync: true`), a caller's timeout is
  discarded along with the request it would have made. A "pull to
  refresh" built on `oneShotSync(timeout: Duration.zero)` can therefore
  wait on an already-open long-poll for up to its full timeout, asking
  the server nothing. `forceSyncNow(client)`
  (`lib/core/matrix/force_sync.dart`) is the correct way to force a real
  round trip: call `abortSync()` first (blackholes the in-flight
  long-poll — `_currentSyncId = -1`, response dropped, `_currentSync`
  cleared — safe because a blackholed sync never advances `prevBatch`,
  so the next request asks from the same point), then issue the
  zero-timeout `oneShotSync`, then restore the loop. Any new "refresh
  now" feature must go through `forceSyncNow`, not a bare `oneShotSync`
  call.
- **`abortSync()` sets `backgroundSync = false` as a side effect, and
  the SDK exposes no getter for its prior value.** `forceSyncNow` must
  restore it to `true` unconditionally in a `finally`, not to a saved
  value — an exception between the two calls (e.g. an offline pull)
  would otherwise leave the app with no sync loop for the rest of the
  session. This unconditional restore is specific to `forceSyncNow`'s
  normal callers (pull-to-refresh, post-recovery refresh) — background
  clients (push engines, notification actions) deliberately run with no
  sync loop and must never call it. `didChangeAppLifecycleState`'s background-pause
  relies on this same side effect the opposite way: `abortSync()` on
  `paused` leaves `backgroundSync` false until `resumed` explicitly sets
  it back to `true` — there is no third caller racing to restore it
  in between, unlike `forceSyncNow`.

## Extension Guidance
- New cross-cutting concerns (another global stream-derived UI signal,
  another startup step) belong in this layer, following the existing
  shape: a `StreamProvider` seeded with a synchronous current value
  where the underlying stream doesn't replay (`isLoggedInProvider`,
  `connectionStatusProvider` are the template), read via `ref.watch`/`ref.read`
  directly in screens — not behind a new repository abstraction.
- A new background entry point (engine or isolate) opens its client only
  through `createMatrixClient(backgroundSync: false)` (background lease, no
  key minting, no store clearing) and handles `ClientLeaseDenied`. It calls
  `installUserAgent()` first and never `CallNotificationService.initialize()`
  with the default claim (`calls.md`).
- Do not reintroduce sequential blocking init. Any new setup step in
  `main()` or `createMatrixClient()` that doesn't depend on an existing
  step's result should start concurrently and be joined only where a
  real dependency exists (as vodozemac init is joined before any crypto
  use, not before database open).
- Any new use of `client.setState`-driven data that a screen needs to
  react to live should double-check which stream actually fires
  (`onSync` vs. `onRoomState` vs. `onSyncStatus` are all distinct and
  not interchangeable) rather than assuming `onSync` covers everything.
- A widget that needs to react to app backgrounding/foregrounding
  should follow `_AuthGate`'s `WidgetsBindingObserver` pattern
  (`didChangeAppLifecycleState`), including its "skip the first resume"
  guard where cold start and warm resume need different handling.
- A caught error the user sees gets a fixed sentence (what happened, what
  to do) and never the exception text. The exception goes to
  `logCaught(label, e)` (`core/errors/best_effort.dart`) so logcat keeps
  it. `runBestEffort` stays the tool for failures the user never sees.
  `isConnectionError` (`core/errors/connection_error.dart`) is the one test
  for a network failure; `failureMessage(e, failed:)` turns it into
  "<what failed> Check your connection and try again."
- Global, no-context UI hooks (SnackBar, navigation) go through the
  existing global keys (`globalScaffoldMessengerKey`,
  `globalNavigatorKey`, both wired on `MaterialApp` in `app.dart`)
  rather than introducing a second mechanism.
- A new Swift file or target goes in through the xcodeproj gem (Gotchas).
  Swift the app shares with the share extension goes in `ios/Shared/`, with
  the notification extension in `ios/NotifyShared/`; each file joins both
  targets, and RunnerTests reach it through Runner. Not every class has its
  own file: `WakeLockPlugin` and `ClientLeasePlugin` live in
  `UploadServicePlugin.swift`, `RoomLaunchPlugin` in
  `ApnsTokenPlugin.swift`.
- A new iOS plugin registers in `EngineHost.registerPlugins`, and its Dart
  wrapper no-ops behind a capability flag.
- The iOS Runner compiles in Swift 6 mode. A new channel handler copies
  the shape of the ones in `ios/Runner/`: a `@MainActor` class,
  `@preconcurrency FlutterPlugin` conformance, and
  `@preconcurrency import Flutter`, since Flutter's headers carry no
  concurrency annotations. Blocking work leaves the main actor, either on
  a GCD queue bridged with `withCheckedContinuation` or in a
  `@concurrent nonisolated static` async function returning `sending`.
  `result` is called back on the main actor. Swift 6 also checks this at
  runtime: a handler invoked off the main thread crashes instead of
  racing.

## Dependencies / Integration
- **matrix SDK** (`Client`, `MatrixSdkDatabase`, `NativeImplementations`)
  — the foundation this whole layer wraps.
- **sqflite_sqlcipher** — encrypted local database backing; on Android one
  native connection per path, shared by every engine.
- **vodozemac** (via the SDK's encryption layer) — E2EE; initialized
  once per isolate through `ensureVodozemacInitialized()`. A direct
  dependency too: its `CryptoUtils.pbkdf2` derives the cached SQLCipher key.
- **flutter_riverpod** — provider plumbing for `Client`, login state,
  connectivity.
- Feature layers that build on this one: authentication (`isLoggedInProvider`,
  `_AuthGate`), calls (`CallSession`/`CallEngine`, reachable app-wide via
  the same global navigator key), notification delivery
  (`NotificationDeliveryProvider`, synced to login state in `_AuthGate`),
  room roles/security/event display — all read the shared `Client`
  rather than a layer of their own.
