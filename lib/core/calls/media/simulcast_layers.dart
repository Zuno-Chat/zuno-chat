import 'package:flutter_webrtc/flutter_webrtc.dart'
    show RTCDegradationPreference, RTCRtpEncoding, RTCRtpParameters;

({int width, int height}) captureSizeFor({required bool lowDataMode}) =>
    lowDataMode ? (width: 640, height: 360) : (width: 854, height: 480);

const fullLayerRid = 'h';

typedef SimulcastLayer = ({
  String rid,
  double scaleResolutionDownBy,
  int maxFramerate,
  int maxBitrate,
});

List<SimulcastLayer> simulcastLayersFor({required bool lowDataMode}) => [
  (
    rid: 'q',
    scaleResolutionDownBy: 2.0,
    maxFramerate: 15,
    maxBitrate: lowDataMode ? 150000 : 200000,
  ),
  (
    rid: fullLayerRid,
    scaleResolutionDownBy: 1.0,
    maxFramerate: 30,
    maxBitrate: lowDataMode ? 500000 : 950000,
  ),
];

List<RTCRtpEncoding> simulcastEncodingsFor({required bool lowDataMode}) => [
  for (final layer in simulcastLayersFor(lowDataMode: lowDataMode))
    _write(RTCRtpEncoding(rid: layer.rid), layer),
];

RTCRtpParameters applySimulcastLayers(
  RTCRtpParameters params,
  List<SimulcastLayer> layers,
) {
  final byRid = {for (final layer in layers) layer.rid: layer};
  for (final encoding in params.encodings ?? const <RTCRtpEncoding>[]) {
    if (byRid[encoding.rid] case final layer?) _write(encoding, layer);
  }
  params.degradationPreference = RTCDegradationPreference.MAINTAIN_FRAMERATE;
  return params;
}

RTCRtpEncoding _write(RTCRtpEncoding encoding, SimulcastLayer layer) => encoding
  ..scaleResolutionDownBy = layer.scaleResolutionDownBy
  ..maxFramerate = layer.maxFramerate
  ..maxBitrate = layer.maxBitrate;
