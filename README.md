# Zuno

[![codecov](https://codecov.io/gh/Zuno-Chat/zuno-chat/graph/badge.svg?token=OD3PSTSAEH)](https://codecov.io/gh/Zuno-Chat/zuno-chat)

A free, open-source Matrix chat client for Android 8.0+ and iOS 18+,
written in Flutter. It signs in to any Matrix homeserver.

## Features

| Area | How Zuno differs |
|---|---|
| Security UX | Device keys, verification, cross-signing and key backup are presented as one story: recovery, device approval and confirming people. No mechanism is named, and nothing shows unless it needs action. |
| Security alerts | Alerts for changes that could let a device read along, including a new device of a contact without cross-signing, which default key sharing accepts silently. |
| Calls | Signaling loosely modeled on MatrixRTC, over an SFU the homeserver picks: Cloudflare or LiveKit. Calls connect Zuno to Zuno only. |
| Call rings | A Synapse module rings the callee from the server with a sealed push, so a closed app rings without room keys, and Apple and Google learn only that a call arrived. |
| iOS notifications | The notification extension decrypts with a narrow, read-only credential and never holds the account's access token or identity keys. |
| Privacy defaults | Screenshot blocking on Android, an incognito keyboard and a self-clearing clipboard are on from the first launch, and a recovery code is caught before it's sent in a chat. |
| Matrix out of sight | No Matrix terms or full user IDs unless the Matrix experience setting is on. |

Also: chats, rooms and communities, photos, video, voice messages and files,
live location, notifications over FCM, UnifiedPush or APNs, and opt-in
crash reporting.

## Upcoming

- MatrixRTC calls that work with other Matrix clients.
- A custom theme color.
- Voice masking in calls.
- Calls with people on other homeservers.
- Delivery ticks, once Synapse supports delivery receipts (MSC4089).

## Homeservers

Everything works on a plain Matrix homeserver except what these two
Synapse modules enable. zuno.chat runs both.

| Module | Enables |
|---|---|
| [`zuno_calls`](https://github.com/Zuno-Chat/zuno_calls) | Calls on Cloudflare or LiveKit (SFU), whichever the homeserver configures. |
| [`zuno_push`](https://github.com/Zuno-Chat/zuno_push) | Native rings on a closed app (CallKit on iOS, a call notification on Android), and message content in iOS notifications. |

Both are AGPL-3.0, each set up as its repository describes.

## Build and run

Needs Flutter. iOS also needs a Mac with Xcode and CocoaPods.

```
flutter pub get
flutter run        # on a physical iPhone, add --profile
flutter test
```

- Release builds need a `.env` (copy `.env.example`); without it, crash
  reporting is off. Signing is in `KEYSTORE.md`.
- FCM needs Zuno's `google-services.json`, which isn't in the repo; without
  it, Android uses UnifiedPush or background sync.

## Layout

| Path | Holds |
|---|---|
| `lib/` | The app: shared code in `core/`, screens in `features/` |
| `packages/` | Emoji picker, network clients, Android notifications |
| `android/`, `ios/` | Native code and extensions |
| `test/` | Tests |
| `docs/features/` | How each feature works |

## Contributing

Issues and pull requests are welcome. A change comes with tests, adds no
code comments, and passes the checks that run on every pull request.

## Security

Report a vulnerability privately through the repository's Security tab, not
in a public issue.

## License

GNU Affero General Public License, version 3 or later. See
[LICENSE](LICENSE). Copyright (C) 2026 The Zuno Chat Authors.

The `matrix` and `flutter_vodozemac` libraries are AGPL-3.0, so a fork
cannot be relicensed more permissively. The Zuno name and logo are not
covered by the license: a modified build needs its own name and icon.
