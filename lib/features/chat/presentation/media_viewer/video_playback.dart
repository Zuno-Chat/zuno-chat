import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/errors/caught_errors.dart';
import '../../../../core/matrix/attachment_actions.dart';
import '../../../../core/matrix/media_audio_session.dart';
import '../../../../core/matrix/playable_media_file.dart';
import '../../../../core/platform/platform_capabilities.dart';

class VideoPlayback extends ChangeNotifier implements MediaPlayback {
  final Event event;
  final MediaAudioSession _audio;
  VideoPlayerController? _controller;
  bool _loading = false;
  Object? _error;
  bool _muted;
  bool _wasPlaying = false;
  bool _holdsSession = false;
  bool _disposed = false;

  VideoPlayback(this.event, {required this._muted, required this._audio});

  @override
  MediaSound get sound => MediaSound.video;

  VideoPlayerController? get controller => _controller;
  Object? get error => _error;
  bool get playing => _controller?.value.isPlaying ?? false;

  Future<void> start() async {
    final loaded = _controller;
    if (loaded != null) return _play(loaded);
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final controller = await _open();
      if (_disposed) {
        await controller.dispose();
        return;
      }
      _controller = controller..addListener(_followController);
      _loading = false;
      notifyListeners();
      await _play(controller);
    } catch (e, s) {
      reportCaught('load video', e, s);
      if (_disposed) return;
      _loading = false;
      _error = e;
      notifyListeners();
    }
  }

  Future<VideoPlayerController> _open() async {
    final file = await playableMediaFile(
      await cachedAttachmentFile(event),
      mimetype: attachmentMimeType(event),
      fileName: attachmentFileName(event),
      fallbackExtension: '.mp4',
      capabilities: ambientCapabilities,
    );
    final controller = VideoPlayerController.file(
      file,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    try {
      await controller.initialize();
      if (_muted) await controller.setVolume(0);
    } catch (_) {
      await controller.dispose();
      rethrow;
    }
    return controller;
  }

  Future<void> _play(VideoPlayerController controller) async {
    await _holdSession(!_muted);
    await controller.play();
  }

  Future<void> _holdSession(bool hold) async {
    if (hold == _holdsSession) return;
    _holdsSession = hold;
    await (hold ? _audio.beginPlayback(this) : _audio.endPlayback(this));
  }

  void _followController() {
    final playing = this.playing;
    if (playing == _wasPlaying) return;
    _wasPlaying = playing;
    if (!playing) unawaited(_holdSession(false));
    notifyListeners();
  }

  void togglePlay() {
    final controller = _controller;
    if (controller == null) return;
    unawaited(
      controller.value.isPlaying ? controller.pause() : _play(controller),
    );
  }

  @override
  Future<void> pause() async => _controller?.pause();

  Future<void> seekTo(Duration position) async => _controller?.seekTo(position);

  set muted(bool value) {
    if (_muted == value) return;
    _muted = value;
    final controller = _controller;
    if (controller == null) return;
    unawaited(controller.setVolume(value ? 0 : 1));
    if (playing) unawaited(_holdSession(!value));
  }

  @override
  void dispose() {
    _disposed = true;
    if (_holdsSession) {
      _holdsSession = false;
      unawaited(_audio.endPlayback(this));
    }
    final controller = _controller;
    if (controller != null) {
      controller.removeListener(_followController);
      unawaited(controller.dispose());
    }
    super.dispose();
  }
}
