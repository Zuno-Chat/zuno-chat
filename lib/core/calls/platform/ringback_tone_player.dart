import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../errors/caught_errors.dart';
import '../../notifications/notification_sound_settings.dart';
import '../../platform/platform_capabilities.dart';

const _callsChannel = MethodChannel('zuno/calls');

Future<void> _invokeCallChannel(String method) async {
  try {
    await _callsChannel.invokeMethod<void>(method);
  } catch (e, s) {
    if (e is! MissingPluginException) reportCaught('ringback $method', e, s);
  }
}

abstract interface class RingbackTonePlayer {
  Future<void> start();

  Future<void> stop();
}

RingbackTonePlayer ringbackTonePlayerFor(PlatformCapabilities capabilities) =>
    capabilities.callKit || capabilities.nativeCallAudio
    ? NativeRingbackTonePlayer.instance
    : const NoopRingbackTonePlayer();

final ringbackTonePlayerProvider = Provider<RingbackTonePlayer>(
  (ref) => ringbackTonePlayerFor(ref.watch(platformCapabilitiesProvider)),
);

class NativeRingbackTonePlayer implements RingbackTonePlayer {
  @visibleForTesting
  NativeRingbackTonePlayer();
  static final instance = NativeRingbackTonePlayer();

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

  @visibleForTesting
  bool get isPlaying => _playing;

  @visibleForTesting
  static void forgetForTest() => instance._playing = false;
}

class NoopRingbackTonePlayer implements RingbackTonePlayer {
  const NoopRingbackTonePlayer();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}
