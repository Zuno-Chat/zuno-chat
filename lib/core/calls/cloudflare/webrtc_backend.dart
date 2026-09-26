import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

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

  webrtc.FrameCryptorFactory get frameCryptorFactory =>
      webrtc.frameCryptorFactory;

  Future<bool> switchCamera(webrtc.MediaStreamTrack track) =>
      webrtc.Helper.switchCamera(track);
}
