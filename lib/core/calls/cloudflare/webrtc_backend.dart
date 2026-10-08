import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

const _callsChannel = MethodChannel('zuno/calls');

typedef PlaceholderVideo = ({
  webrtc.MediaStream stream,
  webrtc.MediaStreamTrack track,
});

class _PlaceholderVideoTrack extends webrtc.MediaStreamTrack {
  _PlaceholderVideoTrack(this.id);

  @override
  final String id;
  @override
  String get kind => 'video';
  @override
  String get label => 'placeholder';
  @override
  bool enabled = true;
  @override
  bool get muted => false;

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class WebRtcBackend {
  const WebRtcBackend();

  Future<webrtc.RTCPeerConnection> createPeerConnection(
    Map<String, dynamic> configuration,
  ) => webrtc.createPeerConnection(configuration);

  Future<webrtc.MediaStream> getUserMedia(Map<String, dynamic> constraints) =>
      webrtc.navigator.mediaDevices.getUserMedia(constraints);

  Future<webrtc.MediaStream> createLocalMediaStream(String label) =>
      webrtc.createLocalMediaStream(label);

  Future<PlaceholderVideo?> createPlaceholderVideo() async {
    final stream = await webrtc.createLocalMediaStream('placeholder_video');
    String? trackId;
    try {
      trackId = await _callsChannel.invokeMethod<String>(
        'attachPlaceholderVideo',
        {'streamId': stream.id},
      );
    } on MissingPluginException {
      trackId = null;
    } catch (_) {
      await stream.dispose();
      rethrow;
    }
    if (trackId == null) {
      await stream.dispose();
      return null;
    }
    return (stream: stream, track: _PlaceholderVideoTrack(trackId));
  }

  Future<void> releasePlaceholderVideo(PlaceholderVideo placeholder) async {
    await placeholder.stream.dispose();
    await _callsChannel.invokeMethod<void>('releasePlaceholderVideo', {
      'trackId': placeholder.track.id,
    });
  }

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
