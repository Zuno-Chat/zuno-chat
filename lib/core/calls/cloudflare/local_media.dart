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
  MediaStream? _cameraCapture;
  Future<void>? _opening;
  bool _closed = false;
  final _microphoneCaptured = Completer<void>();

  MediaStream? get microphoneStream => _microphoneStream;
  MediaStream? get cameraStream => _cameraStream;
  MediaStreamTrack? get microphone =>
      _microphoneStream?.getAudioTracks().firstOrNull;
  MediaStreamTrack? get camera => _cameraStream?.getVideoTracks().firstOrNull;
  Future<void> get microphoneCaptured => _microphoneCaptured.future;

  Map<String, Object?> get _videoConstraints {
    final size = captureSizeFor(lowDataMode: lowDataMode);
    return {
      'facingMode': frontCamera ? 'user' : 'environment',
      'width': size.width,
      'height': size.height,
      'frameRate': 30,
    };
  }

  Future<void> open() => _opening ??= _open();

  Future<void> _open() async {
    final stream = await _webRtc.getUserMedia({
      'audio': true,
      'video': cameraEnabled && camera == null ? _videoConstraints : false,
    });
    _microphoneCaptured.complete();
    if (_closed) {
      await quietly(stream.dispose);
      return;
    }
    final microphone = await _webRtc.createLocalMediaStream('local_audio');
    _microphoneStream = microphone;
    for (final track in stream.getAudioTracks()) {
      await microphone.addTrack(track);
    }
    final videoTracks = stream.getVideoTracks();
    if (videoTracks.isNotEmpty) {
      final camera = await _webRtc.createLocalMediaStream('local_video');
      _cameraStream = camera;
      for (final track in videoTracks) {
        await camera.addTrack(track);
      }
    }
    if (_closed) {
      await close();
      await quietly(stream.dispose);
    }
  }

  Future<void> startCamera() async {
    final captured = await _webRtc.getUserMedia({
      'audio': false,
      'video': _videoConstraints,
    });
    MediaStream? wrapper;
    try {
      wrapper = await _webRtc.createLocalMediaStream('local_video');
      for (final track in captured.getVideoTracks()) {
        await wrapper.addTrack(track);
      }
    } catch (_) {
      await quietly(wrapper?.dispose);
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
    _microphoneStream = null;
    await quietly(microphone?.dispose);
    await stopCamera();
  }
}
