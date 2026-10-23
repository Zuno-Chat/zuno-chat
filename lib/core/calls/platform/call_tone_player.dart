import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../errors/caught_errors.dart';
import '../../notifications/settings/notification_sound_settings.dart';
import '../../platform/platform_capabilities.dart';

const _callsChannel = MethodChannel('zuno/calls');

Future<void> _invokeCallChannel(String method, [Object? arguments]) async {
  try {
    await _callsChannel.invokeMethod<void>(method, arguments);
  } catch (e, s) {
    if (e is! MissingPluginException) reportCaught('call tone $method', e, s);
  }
}

enum CallTone {
  ringback(
    'startRingbackTone',
    'stopRingbackTone',
    'assets/sounds/ringback.wav',
  ),
  waiting(
    'startWaitingTone',
    'stopWaitingTone',
    'assets/sounds/call_waiting.wav',
  );

  const CallTone(this._start, this._stop, this.asset);

  final String _start;
  final String _stop;
  final String asset;
}

abstract interface class CallTonePlayer {
  Future<void> start(CallTone tone);

  Future<void> stop(CallTone tone);
}

CallTonePlayer callTonePlayerFor(PlatformCapabilities capabilities) {
  if (capabilities.callKit) return NativeCallTonePlayer.callKit;
  if (capabilities.nativeCallAudio) return NativeCallTonePlayer.callAudio;
  return const NoopCallTonePlayer();
}

final callTonePlayerProvider = Provider<CallTonePlayer>(
  (ref) => callTonePlayerFor(ref.watch(platformCapabilitiesProvider)),
);

class NativeCallTonePlayer implements CallTonePlayer {
  NativeCallTonePlayer._(this._native);

  static final callKit = NativeCallTonePlayer._({CallTone.ringback});
  static final callAudio = NativeCallTonePlayer._(CallTone.values.toSet());

  final Set<CallTone> _native;
  final _playing = <CallTone>{};

  @override
  Future<void> start(CallTone tone) async {
    if (!_native.contains(tone) || !_playing.add(tone)) return;
    final settings = await loadNotificationSoundSettings(
      fromOtherIsolates: false,
    );
    if (!_playing.contains(tone) || !settings.ringtone) {
      _playing.remove(tone);
      return;
    }
    await _invokeCallChannel(tone._start, {'asset': tone.asset});
  }

  @override
  Future<void> stop(CallTone tone) async {
    if (!_playing.remove(tone)) return;
    await _invokeCallChannel(tone._stop);
  }

  @visibleForTesting
  Set<CallTone> get playing => {..._playing};

  @visibleForTesting
  static void forgetForTest() {
    callKit._playing.clear();
    callAudio._playing.clear();
  }
}

class NoopCallTonePlayer implements CallTonePlayer {
  const NoopCallTonePlayer();

  @override
  Future<void> start(CallTone tone) async {}

  @override
  Future<void> stop(CallTone tone) async {}
}
