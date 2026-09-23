# Zuno

A Matrix chat client for Android, written in Flutter.

Android is the only supported platform. iOS is not built yet.

## Features

- One-to-one chats and rooms, end-to-end encrypted.
- Device verification by QR code or emoji, and a recovery code for key backup.
- Voice and video calls, one-to-one and group.
- Photos, video, voice messages, files and per-room media galleries.
- Location pins.
- Notifications through FCM, UnifiedPush or a background service.
- Sharing into the app from other apps.
- Room roles and permissions.
- Crash reporting that is off by default, release builds only, with message
  content and identifiers removed.

## Homeservers

The app signs in to any Matrix homeserver. Some features expect extras
from the homeserver: Synapse modules for calls and TURN credentials and for
sign-up codes, an FCM push gateway, and a tile source for location messages
advertised under `im.zuno.tiles` in its `.well-known/matrix/client`.
Without them those features are unavailable and everything else works.

## Build and run

Requires Flutter with Dart 3.13 or later, and an Android device or emulator.

```
flutter pub get
flutter run                    # debug build on a connected device or emulator
flutter test
flutter analyze
flutter build apk --release --dart-define-from-file=.env
```

- `.env` holds build-time values such as the crash-reporting DSN; copy
  `.env.example`. Without it a release build ships with crash reporting off.
- Release builds are signed with `android/key.properties`; see
  `KEYSTORE.md`. Without it the build falls back to the debug key, which
  must never be distributed.
- Push over FCM needs a Firebase project: run `flutterfire configure` or
  drop its `google-services.json` into `android/app/`. Without it the app
  still builds, and notifications come through UnifiedPush or the
  background service, picked in Settings.

## Layout

- `lib/core/` — shared logic: the Matrix client, calls, notifications,
  security, location, theme and motion.
- `lib/features/<feature>/presentation/` — screens, one folder per feature.
- `packages/` — three small Android plugins for call-style notifications,
  conversation shortcuts and vibration.
- `android/app/src/main/kotlin/` — services, receivers and device checks.
- `test/` — mirrors `lib/`, with fakes in `test/helpers/`.

There is one `Client` for the whole app and no service layer: screens call
the Matrix SDK directly, and the SDK's types are the app state.

## Contributing

Issues and pull requests are welcome. For a change to be merged:

- `flutter analyze` is clean and `flutter test` passes.
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
