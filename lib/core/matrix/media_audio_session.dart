import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../async/serial_lock.dart';
import '../calls/active_call_provider.dart';
import '../errors/caught_errors.dart';
import '../platform/platform_capabilities.dart';

final voicePlaybackSession = AudioSessionConfiguration(
  avAudioSessionCategory: AVAudioSessionCategory.playback,
  avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
  avAudioSessionMode: AVAudioSessionMode.spokenAudio,
  avAudioSessionSetActiveOptions:
      AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
  androidAudioAttributes: const AndroidAudioAttributes(
    contentType: AndroidAudioContentType.speech,
    usage: AndroidAudioUsage.media,
  ),
  androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransient,
  androidWillPauseWhenDucked: true,
);

final videoPlaybackSession = AudioSessionConfiguration(
  avAudioSessionCategory: AVAudioSessionCategory.playback,
  avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
  avAudioSessionMode: AVAudioSessionMode.moviePlayback,
  avAudioSessionSetActiveOptions:
      AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
  androidAudioAttributes: const AndroidAudioAttributes(
    contentType: AndroidAudioContentType.movie,
    usage: AndroidAudioUsage.media,
  ),
  androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
  androidWillPauseWhenDucked: true,
);

final voiceRecordingSession = AudioSessionConfiguration(
  avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
  avAudioSessionCategoryOptions:
      AVAudioSessionCategoryOptions.defaultToSpeaker |
      AVAudioSessionCategoryOptions.allowBluetooth |
      AVAudioSessionCategoryOptions.allowBluetoothA2dp,
  avAudioSessionMode: AVAudioSessionMode.defaultMode,
  avAudioSessionSetActiveOptions:
      AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
);

final toneSession = AudioSessionConfiguration(
  avAudioSessionCategory: AVAudioSessionCategory.ambient,
  avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
  avAudioSessionMode: AVAudioSessionMode.defaultMode,
);

abstract interface class AudioSessionPort {
  Future<void> configure(AudioSessionConfiguration configuration);

  Future<void> setActive(bool active);

  Stream<void> get interruptions;

  Stream<void> get unplugged;
}

class _PluginAudioSessionPort implements AudioSessionPort {
  const _PluginAudioSessionPort();

  @override
  Future<void> configure(AudioSessionConfiguration configuration) async =>
      (await AudioSession.instance).configure(configuration);

  @override
  Future<void> setActive(bool active) async =>
      (await AudioSession.instance).setActive(active);

  @override
  Stream<void> get interruptions => Stream.fromFuture(AudioSession.instance)
      .asyncExpand<void>(
        (session) =>
            session.interruptionEventStream.where((event) => event.begin),
      );

  @override
  Stream<void> get unplugged =>
      Stream.fromFuture(AudioSession.instance)
          .asyncExpand<void>((session) => session.becomingNoisyEventStream);
}

enum MediaSound { voice, video }

abstract interface class MediaPlayback {
  MediaSound get sound;

  Future<void> pause();
}

final mediaAudioSessionProvider = Provider<MediaAudioSession>((ref) {
  final session = MediaAudioSession(
    ownsRecordingSession: ref
        .watch(platformCapabilitiesProvider)
        .recorderNeedsAudioSession,
    callHoldsAudio: () => ref.read(activeCallProvider) != null,
  );
  ref.listen(activeCallProvider, (previous, next) {
    if (previous != null && next == null) unawaited(session.callEnded());
  });
  ref.onDispose(session.dispose);
  return session;
});

class MediaAudioSession {
  MediaAudioSession({
    required this.ownsRecordingSession,
    required this._callHoldsAudio,
    this._port = const _PluginAudioSessionPort(),
  });

  final bool ownsRecordingSession;
  final bool Function() _callHoldsAudio;
  final AudioSessionPort _port;
  final _turns = SerialLock();
  final _playing = <MediaPlayback>{};
  final _recording = <Object>{};
  final _tones = <Object>{};
  List<StreamSubscription<void>>? _pauseRequests;
  AudioSessionConfiguration? _held;

  Future<void> beginPlayback(MediaPlayback holder) {
    _pauseRequests ??= [
      _port.interruptions.listen((_) => _pausePlayback()),
      _port.unplugged.listen((_) => _pausePlayback()),
    ];
    for (final playing in [..._playing]) {
      if (playing.sound != holder.sound) unawaited(playing.pause());
    }
    return _update(() => _playing.add(holder));
  }

  Future<void> endPlayback(MediaPlayback holder) =>
      _update(() => _playing.remove(holder));

  Future<void> callEnded() => _update(() => true);

  void dispose() {
    for (final subscription in _pauseRequests ?? const []) {
      unawaited(subscription.cancel());
    }
  }

  void _pausePlayback() {
    for (final holder in [..._playing]) {
      unawaited(holder.pause());
    }
  }

  bool get isRecording => _recording.isNotEmpty;

  Future<void> beginRecording(Object holder) =>
      _update(() => _recording.add(holder) && ownsRecordingSession);

  Future<void> endRecording(Object holder) =>
      _update(() => _recording.remove(holder) && ownsRecordingSession);

  Future<void> duringTone(Future<void> Function() play) async {
    final tone = Object();
    await _update(() => _tones.add(tone));
    try {
      await play();
    } finally {
      await _update(() => _tones.remove(tone));
    }
  }

  Future<void> _update(bool Function() change) => _turns.run(() async {
    if (!change()) return;
    final wanted = ownsRecordingSession && _recording.isNotEmpty
        ? voiceRecordingSession
        : _playing.any((holder) => holder.sound == MediaSound.video)
        ? videoPlaybackSession
        : _playing.isNotEmpty
        ? voicePlaybackSession
        : _tones.isNotEmpty
        ? toneSession
        : null;
    if (identical(wanted, _held)) return;
    if (_callHoldsAudio()) {
      _held = null;
      return;
    }
    try {
      if (wanted == null) {
        await _port.setActive(false);
      } else {
        await _port.configure(wanted);
        await _port.setActive(true);
      }
      _held = wanted;
    } catch (e, s) {
      _held = null;
      reportCaught('media audio session', e, s);
    }
  });
}
