import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class FakeVideoPlayer extends VideoPlayerPlatform {
  Size size = const Size(1280, 720);
  Duration duration = const Duration(seconds: 42);
  final unplayable = <String>{};
  Completer<void>? loadGate;
  final opened = <String>[];
  final calls = <String>[];
  final _events = <int, StreamController<VideoEvent>>{};
  var _next = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _next++;
    final uri = options.dataSource.uri!;
    opened.add(uri);
    final events = StreamController<VideoEvent>();
    _events[id] = events;
    Future<void> load() async {
      await loadGate?.future;
      if (events.isClosed) return;
      if (unplayable.any(uri.endsWith)) {
        events.addError(
          PlatformException(code: 'VideoError', message: 'cannot open'),
        );
      } else {
        events.add(
          VideoEvent(
            eventType: VideoEventType.initialized,
            size: size,
            duration: duration,
          ),
        );
      }
    }

    unawaited(load());
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    calls.add('dispose');
    await _events.remove(playerId)?.close();
  }

  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(
    int playerId,
    bool preventsDisplaySleepDuringVideoPlayback,
  ) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> play(int playerId) async => calls.add('play');

  @override
  Future<void> pause(int playerId) async => calls.add('pause');

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      Texture(textureId: options.playerId);
}

FakeVideoPlayer installFakeVideoPlayer() {
  final original = VideoPlayerPlatform.instance;
  final fake = FakeVideoPlayer();
  VideoPlayerPlatform.instance = fake;
  addTearDown(() => VideoPlayerPlatform.instance = original);
  return fake;
}
