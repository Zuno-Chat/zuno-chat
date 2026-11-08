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

class PlaceholderVideoSource {
  const PlaceholderVideoSource();

  Future<PlaceholderVideo?> create() async {
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

  Future<void> release(PlaceholderVideo placeholder) async {
    await placeholder.stream.dispose();
    await _callsChannel.invokeMethod<void>('releasePlaceholderVideo', {
      'trackId': placeholder.track.id,
    });
  }
}
