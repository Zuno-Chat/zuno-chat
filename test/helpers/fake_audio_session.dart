import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';

import 'package:zuno/core/matrix/voice_audio_session.dart';

class FakeAudioSessionPort implements AudioSessionPort {
  FakeAudioSessionPort([List<String>? log]) : log = log ?? [];

  final List<String> log;
  final _interruptions = StreamController<void>.broadcast();
  final _unplugged = StreamController<void>.broadcast();
  bool refuse = false;

  void interrupt() => _interruptions.add(null);

  void unplug() => _unplugged.add(null);

  @override
  Stream<void> get interruptions => _interruptions.stream;

  @override
  Stream<void> get unplugged => _unplugged.stream;

  @override
  Future<void> configure(AudioSessionConfiguration configuration) async {
    log.add('configure ${_nameOf(configuration)}');
    if (refuse) throw PlatformException(code: 'refused');
  }

  @override
  Future<void> setActive(bool active) async {
    log.add(active ? 'active' : 'inactive');
  }

  String _nameOf(AudioSessionConfiguration configuration) =>
      identical(configuration, voicePlaybackSession) ? 'playback' : 'recording';
}

VoiceAudioSession fakeVoiceAudioSession(
  FakeAudioSessionPort port, {
  bool ownsRecordingSession = false,
  bool Function()? callHoldsAudio,
}) => VoiceAudioSession(
  ownsRecordingSession: ownsRecordingSession,
  callHoldsAudio: callHoldsAudio ?? () => false,
  port: port,
);
