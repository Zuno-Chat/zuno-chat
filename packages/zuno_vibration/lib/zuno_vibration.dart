// This package is Android-side only. The app talks to it directly over
// its `zuno/vibration` MethodChannel (see
// lib/core/notifications/notification_sound_player.dart in the main
// app) rather than through a Dart API here — there's nothing this
// package needs to expose beyond registering ZunoVibrationPlugin on
// every FlutterEngine the app (or a plugin it depends on, e.g.
// firebase_messaging's own background engine) ever creates, which is
// the one thing a real Flutter plugin gets for free and a hand-attached
// channel does not. See ZunoVibrationPlugin's own doc comment for why
// that distinction is the whole reason this package exists.
