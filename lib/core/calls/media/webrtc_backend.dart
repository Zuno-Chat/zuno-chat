import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

const _callsChannel = MethodChannel('zuno/calls');

class CameraRefused implements Exception {
  const CameraRefused();
}

const _notAllowed = 'NotAllowedError';

class WebRtcBackend {
  const WebRtcBackend();

  Future<webrtc.RTCPeerConnection> createPeerConnection(
    Map<String, dynamic> configuration,
  ) => webrtc.createPeerConnection(configuration);

  Future<webrtc.MediaStream> getUserMedia(
    Map<String, dynamic> constraints,
  ) async {
    try {
      return await webrtc.navigator.mediaDevices.getUserMedia(constraints);
    } catch (error) {
      final cameraOnly = constraints['audio'] != true;
      if (cameraOnly && '$error'.contains(_notAllowed)) {
        throw const CameraRefused();
      }
      rethrow;
    }
  }

  Future<webrtc.MediaStream> createLocalMediaStream(String label) =>
      webrtc.createLocalMediaStream(label);

  Future<void> setMicrophoneMuteMode(webrtc.MicrophoneMuteMode mode) =>
      webrtc.Helper.setMicrophoneMuteMode(mode);

  Future<void> armSystemCallAudio() async {
    await webrtc.WebRTC.initialize();
    await _callsChannel.invokeMethod<void>('armCallAudio');
  }

  webrtc.FrameCryptorFactory get frameCryptorFactory =>
      webrtc.frameCryptorFactory;

  Future<bool> switchCamera(webrtc.MediaStreamTrack track) =>
      webrtc.Helper.switchCamera(track);
}
