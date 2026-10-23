import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

class FakeAudioPlatform extends JustAudioPlatform {
  FakeAudioPlatform([List<String>? log]) : log = log ?? [];

  final List<String> log;
  final calls = <({String method, Object? argument})>[];
  final _players = <_FakeAudioPlayer>[];
  Duration position = Duration.zero;
  bool refusesToPlay = false;

  Iterable<String> get methods => calls.map((call) => call.method);

  Iterable<Object?> named(String method) =>
      calls.where((call) => call.method == method).map((call) => call.argument);

  void finishPlaying() {
    for (final player in _players) {
      player.emit(ProcessingStateMessage.completed);
    }
  }

  void failPlaying() {
    for (final player in _players) {
      player.fail();
    }
  }

  void reportDuration(Duration duration) {
    for (final player in _players) {
      player.duration = duration;
      player.emit(ProcessingStateMessage.ready);
    }
  }

  void _record(String method, [Object? argument]) {
    calls.add((method: method, argument: argument));
    log.add(method);
  }

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final player = _FakeAudioPlayer(request.id, this);
    _players.add(player);
    return player;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
    DisposePlayerRequest request,
  ) async {
    _players.removeWhere((player) => player.id == request.id);
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
    DisposeAllPlayersRequest request,
  ) async {
    _players.clear();
    return DisposeAllPlayersResponse();
  }
}

class _FakeAudioPlayer extends AudioPlayerPlatform {
  _FakeAudioPlayer(super.id, this._platform);

  final FakeAudioPlatform _platform;
  final _events = StreamController<PlaybackEventMessage>.broadcast();
  Duration? duration;

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  void emit(
    ProcessingStateMessage state, {
    Duration? position,
    int? errorCode,
    String? errorMessage,
  }) {
    if (_events.isClosed) return;
    _events.add(
      PlaybackEventMessage(
        processingState: state,
        updateTime: DateTime.now(),
        updatePosition: position ?? _platform.position,
        bufferedPosition: Duration.zero,
        duration: duration,
        icyMetadata: null,
        currentIndex: 0,
        androidAudioSessionId: null,
        errorCode: errorCode,
        errorMessage: errorMessage,
      ),
    );
  }

  void fail() => emit(
    ProcessingStateMessage.idle,
    errorCode: 1,
    errorMessage: 'MEDIA_ERROR_UNKNOWN',
  );

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    _platform._record('load', _uriOf(request.audioSourceMessage));
    if (_platform.refusesToPlay) {
      throw PlatformException(code: 'abort', message: 'Failed to set source.');
    }
    emit(ProcessingStateMessage.ready);
    return LoadResponse(duration: duration);
  }

  String? _uriOf(AudioSourceMessage source) => switch (source) {
    UriAudioSourceMessage(:final uri) => uri,
    ConcatenatingAudioSourceMessage(:final children) when children.isNotEmpty =>
      _uriOf(children.first),
    _ => null,
  };

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    _platform._record('play');
    emit(ProcessingStateMessage.ready);
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    _platform._record('pause');
    return PauseResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    _platform._record('seek', request.position);
    emit(ProcessingStateMessage.ready, position: request.position);
    return SeekResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
    SetShuffleModeRequest request,
  ) async => SetShuffleModeResponse();

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
    SetAndroidAudioAttributesRequest request,
  ) async => SetAndroidAudioAttributesResponse();

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    await _events.close();
    return DisposeResponse();
  }
}

FakeAudioPlatform installFakeAudioPlatform([List<String>? log]) {
  TestWidgetsFlutterBinding.ensureInitialized();
  final original = JustAudioPlatform.instance;
  final fake = FakeAudioPlatform(log);
  JustAudioPlatform.instance = fake;
  addTearDown(() => JustAudioPlatform.instance = original);
  return fake;
}

Future<void> pumpAudioPlayerDisposal(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump();
  }
}
