# App Foundation

## Overview
Cross-cutting infrastructure the rest of the app sits on: a single
app-wide Matrix `Client`, cold start, connectivity awareness, global
error handling, and the Android launch icon/splash. Not a user-facing
feature — every screen depends on this layer.

## Architecture
One `Client` instance for the whole app's lifetime, built by
`createMatrixClient()` (`lib/core/matrix/matrix_client_provider.dart`)
and awaited before `runApp`. There is no repository/service layer:
feature folders (`lib/features/<feature>/presentation/`) hold screens
only, and screens call SDK methods directly (`client.login`,
`room.sendTextEvent`, ...). SDK types (`Client`/`Room`/`Event`/
`Timeline`) *are* the app state — Riverpod providers expose the client
and derived streams, not a separate app-level model.

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
- `connectionStatusProvider` / `isOfflineProvider` — connectivity
  (`connectivity_provider.dart`), see Communication below.
- `uploadProgressHttpClientProvider` — the `UploadProgressHttpClient`
  wrapping `Client.httpClient`, exposed separately because `Client`
  wraps whatever it's given further in `FixedTimeoutHttpClient`, making
  it impractical to unwrap later.

`Client.httpClient` is actually a small chain:
`UploadProgressHttpClient(ZstdResponseHttpClient(IOClient(HttpClient)))`.
The `HttpClient` has a 10 s `connectionTimeout` — connect only, so a
dead route fails fast while a slow upload/download is never cut off.
`ZstdResponseHttpClient` (`zstd_response_http_client.dart`) sits
innermost — it advertises `Accept-Encoding: zstd` on every request and
transparently decompresses any response the homeserver's Cloudflare
front door sends back with `Content-Encoding: zstd`. Decompression-only,
deliberately: Matrix homeservers don't decode a compressed *request*
body, only Cloudflare's edge does that, response-side. Uses the
`zstandard` plugin (federated, official zstd C source, no manual native
setup) via an injectable decompress function, since the real plugin
needs a running platform channel — tests inject a fake instead of
exercising it.

Navigation has exactly one routing decision: `isLoggedInProvider` +
`_AuthGate` (`lib/app.dart`) switch the root route between the auth
flow (`SignedOutEntry`) and `RoomListPage`. Everything else in the app
is `Navigator.push`. `_AuthGate` also owns the cold-start launch checks
(launch shortcut, notification tap, call launch action or ring, pending
ring, launch share), takes a launch share regardless of login (dropped
when logged out) and syncs notification-delivery transports to login
state.

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
  registered in the theme, so every `MaterialPageRoute` slides with no
  call-site change. Movement only, no fade.

## Data & State
The SDK's local database (SQLCipher-encrypted `sqflite`) is the
persistence layer — everything the SDK tracks (access token, Olm
account, Megolm sessions, cached room/event state) lives in one file,
opened in `createMatrixClient()` via `_openDatabase()`. No app-level
database or cache sits alongside it. `client.init()` restores any prior
session from that database and, if logged in, starts the sync loop.

The database is always opened with its key; there is no plaintext
upgrade path, so a plaintext `zuno.db` fails to open rather than being
read unencrypted. `PRAGMA cipher_version` is checked explicitly after
opening (`_assertSqlCipherPresent`) because `PRAGMA key` fails silently
on stock sqlite3 with no other signal.

## Communication
**Cold start.** `main()`'s independent setup steps (notifications,
building the Matrix client, reading stored preferences) run in
parallel, not sequentially — none depends on the others. Inside
`createMatrixClient()`, vodozemac (E2EE) init and opening the local
database likewise run concurrently, joined with an explicit `await`
only where crypto actually needs it. `client.init()` is called with
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
| Device network | `NetworkAvailabilityStreamHandler.kt` → EventChannel `zuno/network` (Android default-network callback) | `noInternet`, after the network stays gone 2 s |
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

**Backgrounding pauses `/sync`, except during a call.**
`_AuthGate.didChangeAppLifecycleState` (`lib/app.dart`) calls
`client.abortSync()` on `paused` and sets `client.backgroundSync = true`
on `resumed`, via the pure predicates
`shouldPauseBackgroundSync`/`shouldResumeBackgroundSync`
(`background_sync_lifecycle.dart`) — both skip this entirely when
`NotificationDeliveryMode.backgroundService` is active, since that mode's
whole purpose is keeping `/sync` alive while backgrounded. The pause
predicate also takes `inCall` (`activeCallProvider != null`) and never
pauses mid-call, since a call learns of the other side leaving only
through sync; when the active call clears while still `paused`,
`_AuthGate` aborts sync at that point. `abortSync`
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
fetches and starting a new call.

## Key Design Decisions
- **Single `Client`, no repository layer** — SDK types are the app
  state; screens call SDK methods directly. Keeps one source of truth
  and avoids a parallel app-level model drifting from the SDK's own.
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
  so the cached-app freezer doesn't stall it.
- **Boot splash matches the Android launch theme exactly** —
  `ZunoBootSplash` (painted at the very first `runApp`, before
  `createMatrixClient()` has even started) and the `loading:` branch of
  `_AuthGate` both render the same `ZunoSplash` widget
  (`lib/core/ui/zuno_splash.dart`), deliberately
  matched pixel-for-pixel (color, mark size) to the OS-drawn
  `LaunchTheme` window background underneath — a cold start paints the
  mark twice, from two independent layers (OS, then Flutter's first
  frame), and any visible mismatch between them reads as two separate
  loading screens rather than one continuous one.

### Launch targets hold the splash, then land without a transition

On the first logged-in build `_AuthGate` keeps the boot splash and runs
every launch check concurrently once (`_handleLaunch`); the root swaps to
`RoomListPage` only after they finish, capped at 2 s. A launch route
pushed by a check is already on top at the swap, so the room list is
never painted alone. Launch pushes use `LaunchRoute`
(`lib/core/navigation/launch_route.dart`: zero forward transition, normal
reverse) and the call router takes `instant: true` for the same reason.
Cost: a plain cold start shows the splash for as long as the checks take,
about a second on a cold process (the active-ring notification query
dominates). Gating on the fast reads only would bring the flash back for
the ring case, so it was not done.

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
  mid-flow on a pushed `LoginPage`.
- **`_AuthGate`'s three `ref.listenManual` subscriptions must not become
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
  matters because the headless `--unifiedpush-bg` isolate calls
  `createMatrixClient()` once per push.
- **The User-Agent is per isolate and per client.** `installUserAgent()`
  (`lib/core/network/user_agent.dart`) sets `HttpOverrides.global`, so
  every dart:io client created afterwards sends
  `Zuno/<version> (Android; im.zuno.chat)` — Matrix SDK, modules, images,
  tiles. It runs first in `_runApp` (covering `--unifiedpush-bg`), in
  `fcmBackgroundHandler` and in the background notification action; a new
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
- **A screen needing a fully synced `Room`/`Timeline` has no test** —
  the fake-database trick (`test/helpers/fake_matrix.dart`) doesn't
  cover sync/pagination, so `RoomPage`, `RoomListPage`, `CallPage` are
  untested at the widget level. Logic that can be pulled out as a pure
  function (e.g. `shouldReturnToRootRoute`, `becameOnline`) is tested
  directly instead — this is *why* several small pure-function modules
  exist alongside otherwise-untestable screens (`shouldReturnToRootRoute`,
  `becameOnline`, `shouldPauseBackgroundSync`/`shouldResumeBackgroundSync`).
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
  normal callers (pull-to-refresh, post-recovery refresh) — the headless
  `--unifiedpush-bg` isolate deliberately runs with no sync loop and
  must never call it. `didChangeAppLifecycleState`'s background-pause
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
- Global, no-context UI hooks (SnackBar, navigation) go through the
  existing global keys (`globalScaffoldMessengerKey`,
  `globalNavigatorKey`, both wired on `MaterialApp` in `app.dart`)
  rather than introducing a second mechanism.

## Dependencies / Integration
- **matrix SDK** (`Client`, `MatrixSdkDatabase`, `NativeImplementations`)
  — the foundation this whole layer wraps.
- **sqflite_sqlcipher** — encrypted local database backing.
- **vodozemac** (via the SDK's encryption layer) — E2EE; initialized
  once per isolate through `ensureVodozemacInitialized()`.
- **flutter_riverpod** — provider plumbing for `Client`, login state,
  connectivity.
- Feature layers that build on this one: authentication (`isLoggedInProvider`,
  `_AuthGate`), calls (`CallSession`/`CallEngine`, reachable app-wide via
  the same global navigator key), notification delivery
  (`NotificationDeliveryProvider`, synced to login state in `_AuthGate`),
  room roles/security/event display — all read the shared `Client`
  rather than a layer of their own.
