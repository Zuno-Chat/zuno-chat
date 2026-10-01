# Platform split — `android` and `ios`

**Status: redesigned 2026-09-26 and built. Supersedes the 2026-09-06
`google`/`foss`/iOS plan that previously lived here.**

Two flavors, `android` and `ios`, resolved in Dart from the running
platform. No Gradle product flavors, no `--flavor` flag, no Xcode scheme
edits: one Android build, one future iOS build. The split exists so an
iPhone build is a matter of writing Swift, not untangling Android from
shared code.

## `foss` dropped (was: F-Droid eligibility)

Decided 2026-09-26. Firebase is a native dependency of the Android app
module (`firebase-messaging` through the BoM, used by `FcmService` and the
FCM router), so a Firebase-free APK needs a flavor that drops that
dependency and those classes. `mobile_scanner` additionally ships ML Kit,
a proprietary blob F-Droid rejects outright. A `foss` flavor would carry
permanent build complexity for a channel we are not pursuing. Reopening
F-Droid is a fresh decision that must solve both: the FCM split, and the
scanner swap (`flutter_zxing`; gotcha — the Matrix verification QR
payload is raw bytes, not text; a String-shaped scanner API corrupts it
silently, and only an on-device scan proves a replacement handles it).

## Why iOS is a flavor in Dart but not in the build

Flutter's `--flavor` on iOS means Xcode schemes plus per-flavor build
configurations inside `project.pbxproj` — hand-editing a file nothing on
Linux can validate. With `foss` gone, Android needs no flavor axis either,
so neither platform passes `--flavor`; Dart resolves from `Platform.isIOS`.
Code names the axis `AppPlatform`, because platform is what it truthfully
is once no build-time flavor exists.

## The Dart boundary

- `lib/core/platform/app_platform.dart` — `enum AppPlatform { android,
  ios }`; resolution is `Platform.isIOS ? ios : android`. Under
  `flutter test` this is `android`, matching every existing test.
- `lib/core/platform/platform_capabilities.dart` — pure
  `capabilitiesFor(AppPlatform)` returning a `PlatformCapabilities` value,
  exposed as the overridable `platformCapabilitiesProvider`. Same idiom as
  `accountSecurityStatus`: a table-tested function, not a service.
- **Capability flag + safe no-op by default; an interface only where iOS
  genuinely reimplements** (the call seams). An interface with one real
  implementation and a no-op is a capability flag with extra ceremony.
- Call sites never read `Platform.isIOS` directly — they consult the
  provider or take injected capabilities, so the iOS path is testable on
  Linux.
- An iOS `false` means "no equivalent built yet", except Android concepts
  that stay `false` for good: `atomicDatabaseBatches`, `batteryExemption`,
  `backgroundDataRestriction`, `autostartSettings`, `lockScreenCallUi`,
  `foregroundSyncService`, `vibrationPatterns`, `keyboardLearningOptOut`,
  `homeScreenShortcuts` (pinning), `fullScreenIntent` (its
  permission UI only), and the seam selectors `nativeIncomingRingUi`,
  `callForegroundService`, `nativeRingbackTone` (CallKit is a new branch
  per factory, never a flip).

The gated surface: every `zuno/*` platform channel in `lib/`
(notifications, call ring/ongoing/ringback presentation, push wake locks,
FCM delivery, background sync, shortcuts and room opens, conversations,
inbound share, screen security, clipboard, device safety, image/video
processing, upload service, vibration, wake locks, the client lease,
network, sign-out wipe). Ungated, each throws `MissingPluginException` on
iOS and surfaces as a red SnackBar.

## Call seams

`lib/core/calls/platform/` — where CallKit and Android differ:
`IncomingCallPresenter` (full-screen-intent notification ↔ CallKit report),
`RingbackTonePlayer` (`ToneGenerator` ↔ native `AVAudioPlayer`),
`SystemCall` (none ↔ the CallKit call) and `CallAudioOutput` (flutter_webrtc
↔ native routes). `OngoingCallPresenter` stays a no-op on iOS: the session
layer drives the CallKit call (`calls.md`).

The risk: `call_notification_service.dart` also owns cross-isolate decline
and message-action routing (`IsolateNameServer` routes with a ping, accept
and done hand-off in `live_isolate_route.dart`, the headless response
handler) — none of it platform-specific, and the most subtle code in the
app. The seam cuts between how a ring is *presented* and how a decline is
*routed*; the port machinery stays put. This step lands alone, call tests
green on both sides.

## Notification delivery

`NotificationDeliveryMode` gains `apns` (`ApnsDeliveryProvider`, APNs
through Sygnal: `notifications.md`). Android keeps `fcm` as its default;
iOS defaults to `apns`, its only mode.

- The Settings picker iterates `capabilities.deliveryModes`, not `values`.
  With one mode there is no Delivery row or page at all; a push failure
  shows as a problem row with its action on the Notifications page, beside
  the home banner.
- A stored mode unavailable on this platform falls back to the platform
  default — otherwise a carried-over preference selects a dead transport
  and silently delivers nothing (the pusher-left-behind failure class).
- `_syncNotificationDelivery`'s stop-everything-else loop over `values`
  stays: the cheapest guarantee no two transports run at once.

## iOS build prerequisites

- `ios/Runner/Info.plist` now carries the usage-description keys (camera,
  microphone, photo library read + add) and `UIBackgroundModes` (`voip`,
  `audio`, `remote-notification`) — on iOS a missing key is a hard crash on
  first use, not a denied permission.
- Android-only dependencies: `unifiedpush` and the local `packages/`
  plugins `zuno_vibration`, `zuno_call_style`, `zuno_notifications` (each
  pubspec declares only `android`). Every other plugin has an iOS
  implementation. Each call into them is gated or a clean no-op.
- `docs/plan-ios-native.md` enumerates the Mac-session work: native
  handlers per channel, PushKit/CallKit behind the seams, APNs + Sygnal,
  entitlements.

## Sequencing

1. `AppPlatform` + capability layer + tests (no behavior change).
2. Gate the 16 channels: capability check or clean no-op each.
3. Delivery modes: `apns`, capability-driven picker, stored-mode fallback,
   battery-exemption row/onboarding gating.
4. Call seams — alone.
5. `Info.plist` keys; `docs/plan-ios-native.md`.
6. On ship: CLAUDE.md architecture entry, `app-foundation.md`, qualify the
   iOS line in `docs/design-spec-excluded.md`.
