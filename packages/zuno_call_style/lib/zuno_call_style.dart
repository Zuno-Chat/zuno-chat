// This package is Android-side only. The app talks to it directly over
// its `zuno/call_style` MethodChannel (see
// lib/core/calls/notifications/call_notification_service.dart in the main
// app) rather than through a Dart API here — there's nothing this package
// needs to expose beyond registering ZunoCallStylePlugin on every
// FlutterEngine the app (or a plugin it depends on, e.g.
// firebase_messaging's own background engine) ever creates, which is the
// one thing a real Flutter plugin gets for free and a hand-attached
// channel does not. See ZunoCallStylePlugin's own doc comment for why
// that distinction is the whole reason this package exists.
