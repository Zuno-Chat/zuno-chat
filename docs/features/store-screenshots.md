# Store screenshots

`tool/screenshots/` renders the real `RoomListPage`, `RoomPage` and
`CallView` with made-up people and messages, and writes RGB PNGs to
`build/screenshots/`. Run `flutter test tool/screenshots`; it lives outside
`test/`, so the suite never runs it. Uploading is by hand: the release
pipeline never touches screenshots (`releases.md`).

## Devices

| Name | Logical size @ ratio | Output | Store slot |
|---|---|---|---|
| `iphone-6.9in` | 440×956 @3 | 1320×2868 | App Store 6.9" (scaled down for smaller iPhones) |
| `ipad-13in` | 1032×1376 @2 | 2064×2752 | App Store 13" iPad |
| `android-phone` | 360×640 @3 | 1080×1920 | Play phone, 9:16 for promotion eligibility |
| `android-tablet-10in` | 800×1280 @2 | 1600×2560 | Play 10" tablet |

Each device writes the chat list and a room, in light and dark, plus a
voice call.

## Decisions

- **Rendered, not captured.** Shots need no device, account or real data.
  The clock is fixed at 9:41 on the current day, so reruns differ only in
  their date labels.
- **RGB, no alpha.** Play rejects screenshots with an alpha channel.
- **Calls are dark only**, because `CallPage` always wraps `zunoDarkTheme`.
- **No video calls.** `RTCVideoView` draws a native texture that a test
  cannot fill, so a video call would render as an avatar on black. Real video
  needs a device screenshot.

## Gotchas

- **One test file per device.** `ThemeData` fixes its `platform`
  (typography, back icon) from `defaultTargetPlatform` when `zunoLightTheme`
  is first built, so a second platform in the same isolate would get the
  first one's look.
- **Fonts are loaded by hand**, since tests otherwise draw text in a
  placeholder font. Roboto and MaterialIcons come from the Flutter SDK cache
  (found from `Platform.resolvedExecutable`), and SF from
  `/System/Library/Fonts/SFNS.ttf`, so iOS shots need macOS.
- **The analyzer does not treat `tool/` as test code**, so the screenshots
  cannot use `@visibleForTesting` members. Preferences come from a mocked
  platform channel instead, and capabilities from a
  `platformCapabilitiesProvider` override.
- **Encrypted rooms need `encryptionEnabled`**, which a `Client` subclass
  overrides to true. Otherwise `canSendDefaultMessages` is false and
  `RoomPage` hides the composer.
- **Shots have no status bar, avatars are letters, and messages carry no
  photos or emoji**: a test loads no images and has no emoji font.
