import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../notifications/notification_sound_settings.dart';
import '../../platform/platform_capabilities.dart';

const _callsChannel = MethodChannel('zuno/calls');

Future<void> _invokeCallChannel(String method) async {
  try {
    await _callsChannel.invokeMethod<void>(method);
  } catch (_) {}
}

abstract interface class RingbackTonePlayer {
  Future<void> start();

  Future<void> stop();

  Future<void> restartForRouteChange();
}

RingbackTonePlayer ringbackTonePlayerFor(PlatformCapabilities capabilities) {
  if (capabilities.callKit) return CallKitRingbackTonePlayer.instance;
  if (capabilities.nativeRingbackTone) {
    return AndroidRingbackTonePlayer.instance;
  }
  return const NoopRingbackTonePlayer();
}

final ringbackTonePlayerProvider = Provider<RingbackTonePlayer>(
  (ref) => ringbackTonePlayerFor(ref.watch(platformCapabilitiesProvider)),
);

class AndroidRingbackTonePlayer implements RingbackTonePlayer {
  @visibleForTesting
  AndroidRingbackTonePlayer();
  static final instance = AndroidRingbackTonePlayer();

  bool _playing = false;

  @override
  Future<void> start() async {
    if (_playing) return;
    final settings = await loadNotificationSoundSettings();
    if (!settings.ringtone) return;
    _playing = true;
    debugPrint('zuno/sound: ringback start');
    await _invokeCallChannel('startRingbackTone');
  }

  @override
  Future<void> stop() async {
    if (!_playing) return;
    _playing = false;
    debugPrint('zuno/sound: ringback stop');
    await _invokeCallChannel('stopRingbackTone');
  }

  @override
  Future<void> restartForRouteChange() async {
    if (!_playing) return;
    await stop();
    await start();
  }

  @visibleForTesting
  bool get isPlaying => _playing;
}

class CallKitRingbackTonePlayer implements RingbackTonePlayer {
  @visibleForTesting
  CallKitRingbackTonePlayer();
  static final instance = CallKitRingbackTonePlayer();

  bool _playing = false;

  @override
  Future<void> start() async {
    if (_playing) return;
    _playing = true;
    final settings = await loadNotificationSoundSettings();
    if (!_playing || !settings.ringtone) {
      _playing = false;
      return;
    }
    await _invokeCallChannel('startRingbackTone');
  }

  @override
  Future<void> stop() async {
    if (!_playing) return;
    _playing = false;
    await _invokeCallChannel('stopRingbackTone');
  }

  @override
  Future<void> restartForRouteChange() async {}

  @visibleForTesting
  bool get isPlaying => _playing;
}

class NoopRingbackTonePlayer implements RingbackTonePlayer {
  const NoopRingbackTonePlayer();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> restartForRouteChange() async {}
}
