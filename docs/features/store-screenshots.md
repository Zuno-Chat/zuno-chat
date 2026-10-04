# Store screenshots

`tool/screenshots/` renders the real `RoomListPage`, `RoomPage` and
`CallView` with made-up people and messages, and writes RGB PNGs to
`build/screenshots/`. Run `flutter test tool/screenshots`; it lives outside
`test/`, so the suite never runs it.

## Devices

| Name | Logical size @ ratio | Output | Store slot |
|---|---|---|---|
| `iphone-6.9in` | 440×956 @3 | 1320×2868 | App Store 6.9" (scaled down for smaller iPhones) |
| `ipad-13in` | 1032×1376 @2 | 2064×2752 | App Store 13" iPad |
| `android-phone` | 360×640 @3 | 1080×1920 | Play phone, 9:16 for promotion eligibility |
| `android-tablet-10in` | 800×1280 @2 | 1600×2560 | Play 10" tablet |

Each device writes chat list and room (light and dark) plus a voice call.

## Decisions

- **Rendered, not captured.** No device, account or real data; the clock
  is fixed at 9:41 today, so reruns differ only by the date labels.
- **RGB, no alpha.** Play rejects screenshots with an alpha channel.
- **Calls are dark only**, as `CallPage` always wraps `zunoDarkTheme`.
- **No video calls.** `RTCVideoView` draws a native texture a test cannot
  fill, so a video call renders as an avatar on black. Real video needs a
  device screenshot.

## Gotchas

- **One test file per device.** `ThemeData` fixes `platform` (typography,
  back icon) from `defaultTargetPlatform` when `zunoLightTheme` is first
  built, so a second platform in the same isolate gets the first one's look.
- **Fonts are loaded by hand**: Roboto and MaterialIcons from the Flutter
  SDK cache (found from `Platform.resolvedExecutable`), SF from
  `/System/Library/Fonts/SFNS.ttf`. iOS shots therefore need macOS.
- **`tool/` is not test code to the analyzer**, so no `@visibleForTesting`
  members: preferences come from a mocked channel, capabilities from a
  `platformCapabilitiesProvider` override.
- **Encrypted rooms need `encryptionEnabled`** (a `Client` subclass), or
  `canSendDefaultMessages` is false and `RoomPage` hides the composer.
- No status bar, letter avatars, no photos or emoji: tests have no images
  or emoji font.
