import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart'
    show RTCDegradationPreference, RTCRtpEncoding, RTCRtpParameters;
import 'package:zuno/core/calls/media/simulcast_layers.dart';

void main() {
  test('normal calls send h at full size and q at half size and 15 fps', () {
    expect(simulcastLayersFor(lowDataMode: false), [
      (
        rid: 'q',
        scaleResolutionDownBy: 2.0,
        maxFramerate: 15,
        maxBitrate: 200000,
      ),
      (
        rid: 'h',
        scaleResolutionDownBy: 1.0,
        maxFramerate: 30,
        maxBitrate: 950000,
      ),
    ]);
  });

  test('low-data calls send h at full size and q at half size and 15 fps, '
      'each with less', () {
    expect(simulcastLayersFor(lowDataMode: true), [
      (
        rid: 'q',
        scaleResolutionDownBy: 2.0,
        maxFramerate: 15,
        maxBitrate: 150000,
      ),
      (
        rid: 'h',
        scaleResolutionDownBy: 1.0,
        maxFramerate: 30,
        maxBitrate: 500000,
      ),
    ]);
  });

  test('the layers are encodings for the video sender, smallest first', () {
    final encodings = simulcastEncodingsFor(lowDataMode: false);

    expect(
      [
        for (final e in encodings)
          (e.rid, e.scaleResolutionDownBy, e.maxFramerate, e.maxBitrate),
      ],
      [('q', 2.0, 15, 200000), ('h', 1.0, 30, 950000)],
    );
  });

  group('applySimulcastLayers', () {
    final layers = simulcastLayersFor(lowDataMode: false);

    test('writes every layer onto the encoding with its rid', () {
      final params = RTCRtpParameters(
        encodings: [
          RTCRtpEncoding(rid: 'h'),
          RTCRtpEncoding(rid: 'q'),
        ],
      );

      final result = applySimulcastLayers(params, layers);

      final byRid = {for (final e in result.encodings!) e.rid: e};
      expect(byRid['q']!.maxBitrate, 200000);
      expect(byRid['q']!.maxFramerate, 15);
      expect(byRid['q']!.scaleResolutionDownBy, 2.0);
      expect(byRid['h']!.maxBitrate, 950000);
      expect(byRid['h']!.maxFramerate, 30);
      expect(byRid['h']!.scaleResolutionDownBy, 1.0);
      expect(result.encodings, hasLength(2));
    });

    test('keeps the frame rate when the link is short, rather than '
        'flutter_webrtc\'s balanced default', () {
      final result = applySimulcastLayers(
        RTCRtpParameters(
          encodings: [
            RTCRtpEncoding(rid: 'q'),
            RTCRtpEncoding(rid: 'h'),
          ],
          degradationPreference: RTCDegradationPreference.BALANCED,
        ),
        layers,
      );

      expect(
        result.degradationPreference,
        RTCDegradationPreference.MAINTAIN_FRAMERATE,
      );
    });

    test('writes only onto the encodings the sender has, since adding one '
        'would make WebRTC refuse the whole change', () {
      final result = applySimulcastLayers(
        RTCRtpParameters(encodings: [RTCRtpEncoding(rid: 'q')]),
        layers,
      );

      expect([for (final e in result.encodings!) e.rid], ['q']);
      expect(result.encodings!.single.maxBitrate, 200000);
      expect(
        applySimulcastLayers(RTCRtpParameters(), layers).encodings,
        isNull,
      );
    });
  });
}
