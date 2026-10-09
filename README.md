# Zuno

A Matrix chat client for Android and iOS, written in Flutter.

Runs on Android 8.0 and later, and iOS 18 and later.

## Features

- One-to-one chats and rooms, end-to-end encrypted.
- Device verification by QR code or emoji, and a recovery code for key backup.
- Voice and video calls, one-to-one and group, that keep going while you
  use the rest of the app. On iPhone they ring through CallKit.
- Photos, video, voice messages, files and per-room media galleries.
- Location pins and live location.
- Communities (Matrix spaces), with ask to join.
- Notifications with Reply and Mark as read: FCM, UnifiedPush or a
  background service on Android, and APNs on iPhone.
- Sharing into the app from other apps.
- Room roles and permissions.
- Crash reporting that is off by default, release builds only, with message
  content and identifiers removed.

## Homeservers

The app signs in to any Matrix homeserver. Some features need extras on
the homeserver. Without them, those features are unavailable and
everything else works.

| Extra | What it does |
|---|---|
| [`zuno_calls`](https://github.com/Zuno-Chat/zuno_calls) | Synapse module for voice and video calls. It's a proxy for Cloudflare Calls signaling and issues Cloudflare TURN credentials |
| [`zuno_register`](https://github.com/Zuno-Chat/zuno_register) | Synapse module for sign-up codes. It emails a single-use registration token to prove the user controls the inbox |
| [`zuno_push`](https://github.com/Zuno-Chat/zuno_push) | Synapse module that rings a closed iOS app through VoIP pushes, and serves the notification extension's API |
| [Sygnal](https://github.com/element-hq/sygnal) | Push gateway: FCM on Android, APNs on iOS |
| Tile source | Maps for location messages: an `https://` URL template with `{z}`, `{x}` and `{y}`, advertised under `im.zuno.tiles` in `.well-known/matrix/client` |

The modules are AGPL-3.0, like the app. Each installs through the
`modules:` entry in `homeserver.yaml`, documented in its repository.

## Build and run

Requires Flutter with Dart 3.13 or later. Android needs a device or
emulator. iOS needs a Mac with Xcode 27 and CocoaPods, and a simulator or
iPhone.

```
flutter pub get
flutter run                    # debug build on a device, emulator or simulator
flutter run --profile          # a physical iPhone, where a debug build won't launch from the home screen
flutter analyze
flutter test
flutter build apk --config-only && android/gradlew -p android :app:testDebugUnitTest   # Kotlin tests
flutter build ios --config-only --no-codesign && (cd ios && pod install)
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -only-testing:RunnerTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test   # Swift tests
flutter build apk --release --dart-define-from-file=.env
```

- `.env` holds build-time values such as the crash-reporting DSN; copy
  `.env.example`. Without it a release build ships with crash reporting off.
- Android release builds are signed with `android/key.properties`; see
  `KEYSTORE.md`. Without it the build falls back to the debug key, which
  must never be distributed.
- Push over FCM needs a Firebase project: run `flutterfire configure` or
  drop its `google-services.json` into `android/app/`. Without it the app
  still builds, and notifications come through UnifiedPush or the
  background service, picked in Settings.
- iPhone builds are signed for Zuno's Apple team, so on your own device
  set your team and bundle IDs.
- Store releases for both platforms are built and shipped by the release
  pipeline; see `docs/features/releases.md`.

## Layout

- `lib/core/` — shared logic: the Matrix client, calls, notifications,
  security, location, theme and motion.
- `lib/features/<feature>/presentation/` — screens, one folder per feature.
- `packages/` — three small Android plugins for call-style notifications,
  conversation shortcuts and vibration.
- `android/app/src/main/kotlin/` — services, receivers and device checks.
- `ios/` — the app target and its native plugins, the share and
  notification service extensions, and XCTests in `ios/RunnerTests/`.
- `test/` — mirrors `lib/`, with fakes in `test/helpers/`.

There is one `Client` for the whole app and no service layer: screens call
the Matrix SDK directly, and the SDK's types are the app state.

## Contributing

Issues and pull requests are welcome. For a change to be merged:

- `flutter analyze` is clean, and the Flutter, Kotlin and Swift tests pass.
  Pull requests run all four automatically.
- Every change comes with tests: the happy path and a couple of failure
  paths.
- No comments in code, including doc comments. Names and tests carry the
  meaning.
- User-facing text follows `docs/brand-voice.md`.
- Widget tests use the fakes in `test/helpers/` rather than a real database,
  which hangs in sandboxed environments.

## Security

Report a vulnerability privately through the repository's Security tab, not
in a public issue.

## License

Free software under the GNU Affero General Public License, version 3 or any
later version. See [LICENSE](LICENSE).

Copyright (C) 2026 The Zuno Chat Authors.

The app links the `matrix` and `flutter_vodozemac` libraries, which are
AGPL-3.0, so a fork cannot be relicensed more permissively.

The Zuno name and logo are not covered by the license. A modified build
needs its own name and icon.
