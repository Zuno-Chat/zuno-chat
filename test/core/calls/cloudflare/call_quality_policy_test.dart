import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart'
    show RTCRtpParameters, RTCRtpEncoding, StatsReport;

import 'package:zuno/core/calls/cloudflare/call_quality_policy.dart';
import 'package:zuno/core/calls/models/call_quality.dart';

void main() {
  QualitySample clean() => const QualitySample(lossFraction: 0.0, rttMs: 80);
  QualitySample weak() => const QualitySample(lossFraction: 0.06, rttMs: 120);
  QualitySample bad() => const QualitySample(lossFraction: 0.20, rttMs: 900);

  group('CallQualityClassifier happy path', () {
    test('starts good and stays good on clean samples', () {
      final c = CallQualityClassifier();
      expect(c.current, CallQuality.good);
      expect(c.observe(clean()), isNull);
      expect(c.observe(clean()), isNull);
      expect(c.current, CallQuality.good);
    });

    test('needs two consecutive bad samples to step down', () {
      final c = CallQualityClassifier();
      expect(c.observe(weak()), isNull);
      expect(c.current, CallQuality.good);
      expect(c.observe(weak()), CallQuality.degraded);
      expect(c.current, CallQuality.degraded);
    });

    test('steps straight to poor when both bad samples are poor-grade', () {
      final c = CallQualityClassifier();
      c.observe(bad());
      expect(c.observe(bad()), CallQuality.poor);
    });

    test('needs four consecutive clean samples to step up one tier', () {
      final c = CallQualityClassifier();
      c.observe(bad());
      c.observe(bad());
      expect(c.current, CallQuality.poor);
      for (var i = 0; i < 3; i++) {
        expect(c.observe(clean()), isNull);
      }
      expect(c.observe(clean()), CallQuality.degraded);
      for (var i = 0; i < 3; i++) {
        expect(c.observe(clean()), isNull);
      }
      expect(c.observe(clean()), CallQuality.good);
    });
  });

  group('CallQualityClassifier sad paths', () {
    test(
      'two consecutive worse samples of different severity land on the latest',
      () {
        final c = CallQualityClassifier();
        expect(c.observe(weak()), isNull);
        expect(c.observe(bad()), CallQuality.poor);
      },
    );

    test('a single bad sample between clean ones does not flap', () {
      final c = CallQualityClassifier();
      c.observe(clean());
      expect(c.observe(bad()), isNull);
      expect(c.observe(clean()), isNull);
      expect(c.observe(bad()), isNull);
      expect(c.current, CallQuality.good);
    });

    test('a sample inside the hysteresis band does not count as recovery', () {
      final c = CallQualityClassifier();
      c.observe(weak());
      c.observe(weak());
      expect(c.current, CallQuality.degraded);
      const inBand = QualitySample(lossFraction: 0.04, rttMs: 100);
      for (var i = 0; i < 10; i++) {
        expect(c.observe(inBand), isNull);
      }
      expect(c.current, CallQuality.degraded);
    });

    test('missing RTT is treated as fine, loss alone decides', () {
      final c = CallQualityClassifier();
      const lossOnly = QualitySample(lossFraction: 0.15);
      c.observe(lossOnly);
      expect(c.observe(lossOnly), CallQuality.poor);
      const recovered = QualitySample(lossFraction: 0.0);
      for (var i = 0; i < 3; i++) {
        c.observe(recovered);
      }
      expect(c.observe(recovered), CallQuality.degraded);
    });
  });

  group('videoEncodingFor', () {
    test('every tier has explicit non-null limits', () {
      for (final quality in CallQuality.values) {
        for (final lowData in [false, true]) {
          final limits = videoEncodingFor(quality, lowDataMode: lowData);
          expect(limits.scaleResolutionDownBy, greaterThanOrEqualTo(1.0));
          expect(limits.maxFramerate, greaterThan(0));
          expect(limits.maxBitrate, greaterThan(0));
        }
      }
    });

    test('good tier is the capture profile cap', () {
      expect(videoEncodingFor(CallQuality.good, lowDataMode: false), (
        scaleResolutionDownBy: 1.0,
        maxFramerate: 30,
        maxBitrate: 800000,
      ));
      expect(videoEncodingFor(CallQuality.good, lowDataMode: true), (
        scaleResolutionDownBy: 1.0,
        maxFramerate: 24,
        maxBitrate: 500000,
      ));
    });

    test('lower tiers never scale below half resolution', () {
      expect(
        videoEncodingFor(
          CallQuality.degraded,
          lowDataMode: false,
        ).scaleResolutionDownBy,
        2.0,
      );
      expect(
        videoEncodingFor(
          CallQuality.poor,
          lowDataMode: false,
        ).scaleResolutionDownBy,
        2.0,
      );
      expect(
        videoEncodingFor(CallQuality.poor, lowDataMode: false).maxBitrate,
        lessThan(
          videoEncodingFor(CallQuality.degraded, lowDataMode: false).maxBitrate,
        ),
      );
    });
  });

  group('combineQuality', () {
    test('a remote on low bandwidth forces at least degraded', () {
      expect(
        combineQuality(local: CallQuality.good, anyRemoteLowBandwidth: true),
        CallQuality.degraded,
      );
    });

    test('a remote on low bandwidth never improves a poor local reading', () {
      expect(
        combineQuality(local: CallQuality.poor, anyRemoteLowBandwidth: true),
        CallQuality.poor,
      );
    });

    test('no remote signal leaves the local reading alone', () {
      expect(
        combineQuality(local: CallQuality.good, anyRemoteLowBandwidth: false),
        CallQuality.good,
      );
    });
  });

  group('applyVideoEncodingLimits', () {
    const limits = (
      scaleResolutionDownBy: 2.0,
      maxFramerate: 15,
      maxBitrate: 300000,
    );

    test('writes all three limits onto the first encoding', () {
      final params = RTCRtpParameters(
        encodings: [
          RTCRtpEncoding(rid: 'a'),
          RTCRtpEncoding(rid: 'b'),
        ],
      );
      final result = applyVideoEncodingLimits(params, limits);
      final first = result.encodings!.first;
      expect(first.rid, 'a');
      expect(first.scaleResolutionDownBy, 2.0);
      expect(first.maxFramerate, 15);
      expect(first.maxBitrate, 300000);
      expect(result.encodings!.last.rid, 'b');
    });

    test('creates an encoding when the list is empty', () {
      final result = applyVideoEncodingLimits(
        RTCRtpParameters(encodings: []),
        limits,
      );
      expect(result.encodings, hasLength(1));
      expect(result.encodings!.single.maxBitrate, 300000);
    });

    test('a null encodings list is treated as empty', () {
      final result = applyVideoEncodingLimits(RTCRtpParameters(), limits);
      expect(result.encodings, hasLength(1));
    });

    test('returns the same params instance it was given', () {
      final params = RTCRtpParameters(encodings: [RTCRtpEncoding(rid: 'a')]);
      final result = applyVideoEncodingLimits(params, limits);
      expect(identical(result, params), isTrue);
    });
  });

  group('StatsCounters', () {
    StatsReport inbound(int lost, int received) => StatsReport(
      'in$lost',
      'inbound-rtp',
      0,
      {'packetsLost': lost, 'packetsReceived': received},
    );
    StatsReport pair(double rttSeconds, {bool nominated = true}) =>
        StatsReport('pair', 'candidate-pair', 0, {
          'state': nominated ? 'succeeded' : 'in-progress',
          'nominated': nominated,
          'currentRoundTripTime': rttSeconds,
        });

    test(
      'sums inbound counters across audio and video and reads RTT in ms',
      () {
        final counters = StatsCounters.fromReports([
          inbound(2, 100),
          inbound(3, 200),
          pair(0.150),
        ]);
        expect(counters.packetsLost, 5);
        expect(counters.packetsReceived, 300);
        expect(counters.rttMs, 150);
      },
    );

    test(
      'ignores a candidate pair that is neither succeeded nor nominated',
      () {
        final counters = StatsCounters.fromReports([
          pair(0.9, nominated: false),
        ]);
        expect(counters.rttMs, isNull);
      },
    );

    test('sampleSince computes the loss fraction of the delta only', () {
      const previous = StatsCounters(packetsLost: 10, packetsReceived: 1000);
      const current = StatsCounters(
        packetsLost: 20,
        packetsReceived: 1090,
        rttMs: 40,
      );
      final sample = current.sampleSince(previous);
      expect(sample.lossFraction, closeTo(0.1, 1e-9));
      expect(sample.rttMs, 40);
    });

    test('a negative delta (duplicate packets) clamps to zero loss', () {
      const previous = StatsCounters(packetsLost: 10, packetsReceived: 100);
      const current = StatsCounters(packetsLost: 8, packetsReceived: 100);
      expect(current.sampleSince(previous).lossFraction, 0);
    });
  });
}
