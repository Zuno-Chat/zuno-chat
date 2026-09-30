import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

const _callsChannel = MethodChannel('zuno/calls');

class WebRtcBackend {
  const WebRtcBackend();

  Future<webrtc.RTCPeerConnection> createPeerConnection(
    Map<String, dynamic> configuration,
  ) => webrtc.createPeerConnection(configuration);

  Future<webrtc.MediaStream> getUserMedia(Map<String, dynamic> constraints) =>
      webrtc.navigator.mediaDevices.getUserMedia(constraints);

  Future<webrtc.MediaStream> createLocalMediaStream(String label) =>
      webrtc.createLocalMediaStream(label);

  Future<webrtc.RTCRtpCapabilities> getRtpSenderCapabilities(String kind) =>
      webrtc.getRtpSenderCapabilities(kind);

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
