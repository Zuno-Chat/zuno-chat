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

- **Rendered, not captured**, so shots need no device, account or real
  data.
- **RGB, no alpha**, because Play rejects screenshots with an alpha channel.
- **Calls are dark only**, because `CallPage` always uses the dark theme.
- **No video calls**, because a test cannot fill the native video texture,
  so real video needs a device screenshot.

## Gotchas

- **One test file per device**, because `ThemeData` fixes its platform look
  when the theme is first built in an isolate.
- **Fonts are loaded by hand** from the Flutter SDK cache and macOS, so iOS
  shots need a Mac.
- **The analyzer does not treat `tool/` as test code**, so the screenshots
  cannot use `@visibleForTesting` members.
- **Encrypted rooms need a `Client` subclass that reports
  `encryptionEnabled`**, or `RoomPage` hides the composer.
- **Shots have no status bar, photos or emoji, and avatars are letters**,
  because a test loads no images and has no emoji font.
