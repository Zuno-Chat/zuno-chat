import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../errors/best_effort.dart';
import 'call_quality_policy.dart';
import 'webrtc_backend.dart';

class LocalMedia {
  LocalMedia(
    this._webRtc, {
    required this.lowDataMode,
    required this.cameraEnabled,
  });

  final WebRtcBackend _webRtc;
  final bool lowDataMode;
  bool microphoneMuted = false;
  bool cameraEnabled;
  bool frontCamera = true;

  MediaStream? _microphoneStream;
  MediaStream? _cameraStream;
  MediaStream? _capture;
  MediaStream? _cameraCapture;
  Future<void>? _opening;
  bool _closed = false;

  MediaStream? get microphoneStream => _microphoneStream;
  MediaStream? get cameraStream => _cameraStream;
  MediaStreamTrack? get microphone =>
      _microphoneStream?.getAudioTracks().firstOrNull;
  MediaStreamTrack? get camera => _cameraStream?.getVideoTracks().firstOrNull;

  Map<String, Object?> get _videoConstraints {
    final size = captureSizeFor(lowDataMode: lowDataMode);
    return {
      'facingMode': frontCamera ? 'user' : 'environment',
      'width': size.width,
      'height': size.height,
      'frameRate': 30,
    };
  }

  Future<void> open({required bool withCamera}) =>
      _opening ??= _open(withCamera);

  Future<void> _open(bool withCamera) async {
    if (_closed) return;
    final capture = await _webRtc.getUserMedia({
      'audio': true,
      'video': withCamera && cameraEnabled && camera == null
          ? _videoConstraints
          : false,
    });
    if (_closed) {
      await quietly(capture.dispose);
      return;
    }
    MediaStream? microphone;
    MediaStream? cameraStream;
    try {
      microphone = await _adopt('local_audio', capture.getAudioTracks());
      final videoTracks = capture.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        cameraStream = await _adopt('local_video', videoTracks);
      }
    } catch (_) {
      await quietly(microphone?.dispose);
      await quietly(capture.dispose);
      rethrow;
    }
    if (_closed) {
      await quietly(cameraStream?.dispose);
      await quietly(microphone.dispose);
      await quietly(capture.dispose);
      return;
    }
    _capture = capture;
    _microphoneStream = microphone;
    if (cameraStream != null) _cameraStream = cameraStream;
  }

  Future<MediaStream> _adopt(
    String label,
    List<MediaStreamTrack> tracks,
  ) async {
    final stream = await _webRtc.createLocalMediaStream(label);
    try {
      for (final track in tracks) {
        await stream.addTrack(track);
      }
    } catch (_) {
      await quietly(stream.dispose);
      rethrow;
    }
    return stream;
  }

  Future<void> startCamera() async {
    if (_closed) return;
    final captured = await _webRtc.getUserMedia({
      'audio': false,
      'video': _videoConstraints,
    });
    final MediaStream wrapper;
    try {
      wrapper = await _adopt('local_video', captured.getVideoTracks());
    } catch (_) {
      await quietly(captured.dispose);
      rethrow;
    }
    if (_closed) {
      await quietly(wrapper.dispose);
      await quietly(captured.dispose);
      return;
    }
    _cameraStream = wrapper;
    _cameraCapture = captured;
  }

  Future<void> stopCamera() async {
    final camera = _cameraStream;
    final captured = _cameraCapture;
    _cameraStream = null;
    _cameraCapture = null;
    await quietly(camera?.dispose);
    await quietly(captured?.dispose);
  }

  Future<void> switchCamera() async {
    final track = camera;
    if (track == null) {
      frontCamera = !frontCamera;
      return;
    }
    frontCamera = await _webRtc.switchCamera(track);
  }

  void applyTrackState({
    required bool microphoneEncrypted,
    required bool cameraEncrypted,
  }) {
    for (final track
        in _microphoneStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = microphoneEncrypted && !microphoneMuted;
    }
    for (final track
        in _cameraStream?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = cameraEncrypted && cameraEnabled;
    }
  }

  Future<void> close() async {
    _closed = true;
    final microphone = _microphoneStream;
    final capture = _capture;
    _microphoneStream = null;
    _capture = null;
    await quietly(microphone?.dispose);
    await stopCamera();
    await quietly(capture?.dispose);
  }
}
