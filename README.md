# Zuno

Messages that stay between you two.

Zuno is a chat app for Android. Many chat apps are paid for with data about
the people who use them. Zuno has no advertisers and no investors. Accounts
are username-only, every chat is end-to-end encrypted, and the encryption is
Matrix, so anyone can check it.

Accounts live on zuno.chat by default. The homeserver can be changed at
sign-in.

Android is the only supported platform. iOS is not built yet.

## Build

Requires Flutter with Dart 3.13 or later.

```
flutter pub get
flutter run                    # debug build on a connected device or emulator
flutter test
flutter analyze
flutter build apk --release --dart-define-from-file=.env
```

- `.env` holds the crash-reporting DSN; copy `.env.example`.
  Without it a release build ships with crash reporting off.
- Release builds are signed with `android/key.properties`; see
  `KEYSTORE.md`. Without it the build falls back to the debug key, which
  must never be distributed.
- Push over FCM needs a Firebase project: run `flutterfire configure` or
  drop its `google-services.json` into `android/app/`. Without it the app
  still builds, and notifications come through UnifiedPush or the
  background service, picked in Settings.

## Documentation

- `docs/brand-voice.md` — how Zuno sounds.
- `KEYSTORE.md` — release signing.

## License

Zuno is free software under the GNU Affero General Public License, version 3
or any later version. See [LICENSE](LICENSE).

Copyright (C) 2026 The Zuno Chat Authors.

The app links the `matrix` and `flutter_vodozemac` libraries, which are
AGPL-3.0, so a fork cannot be relicensed more permissively.

The Zuno name and logo are not covered by the license. A modified build
needs its own name and icon.
