import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show StatsReport;

import 'package:zuno/core/calls/media/call_quality_policy.dart';
import 'package:zuno/core/calls/models/call_quality.dart';

import '../../../helpers/fake_webrtc.dart';

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

  group('CallQualityClassifier upload bandwidth', () {
    QualitySample heldTo(double? uploadBps) => QualitySample(
      lossFraction: 0,
      rttMs: 80,
      uploadBandwidthBps: uploadBps,
    );

    test('an estimate under 300 kbps is a weak link', () {
      final c = CallQualityClassifier();
      expect(c.observe(heldTo(280000)), isNull);
      expect(c.observe(heldTo(280000)), CallQuality.degraded);
    });

    test('an upload at what WebRTC needs for 360p stays good', () {
      final c = CallQualityClassifier();
      for (var i = 0; i < 5; i++) {
        expect(c.observe(heldTo(300000)), isNull);
      }
      expect(c.current, CallQuality.good);
    });

    test('an estimate under 120 kbps is a poor link', () {
      final c = CallQualityClassifier();
      c.observe(heldTo(90000));
      expect(c.observe(heldTo(90000)), CallQuality.poor);
    });

    test('a weak link clears only at 400 kbps', () {
      final c = CallQualityClassifier();
      c.observe(heldTo(280000));
      c.observe(heldTo(280000));
      for (var i = 0; i < 6; i++) {
        expect(c.observe(heldTo(390000)), isNull);
      }
      expect(c.current, CallQuality.degraded);
      for (var i = 0; i < 3; i++) {
        expect(c.observe(heldTo(400000)), isNull);
      }
      expect(c.observe(heldTo(400000)), CallQuality.good);
    });

    test('a poor link clears only at 160 kbps', () {
      final c = CallQualityClassifier();
      c.observe(heldTo(90000));
      c.observe(heldTo(90000));
      for (var i = 0; i < 6; i++) {
        expect(c.observe(heldTo(150000)), isNull);
      }
      expect(c.current, CallQuality.poor);
      for (var i = 0; i < 3; i++) {
        expect(c.observe(heldTo(160000)), isNull);
      }
      expect(c.observe(heldTo(160000)), CallQuality.degraded);
    });

    test('an estimate that is not judged never holds a tier', () {
      final c = CallQualityClassifier();
      c.observe(heldTo(280000));
      c.observe(heldTo(280000));
      for (var i = 0; i < 3; i++) {
        expect(c.observe(heldTo(null)), isNull);
      }
      expect(c.observe(heldTo(null)), CallQuality.good);
    });
  });

  test('WebRTC starts with video above the weak line, leaving 100 kbps for '
      'audio and packet overhead', () {
    expect(
      startBitrateKbps * 1000 - 100000,
      greaterThanOrEqualTo(CallQualityClassifier.enterDegradedVideoBps),
    );
    expect(
      startBitrateKbps * 1000,
      greaterThanOrEqualTo(CallQualityClassifier.exitDegradedVideoBps),
    );
  });

  group('StatsCounters', () {
    test('reads the round trip in ms', () {
      final counters = StatsCounters.fromReports([
        candidatePair('pair', rttSeconds: 0.150),
      ]);
      expect(counters.rttMs, 150);
    });

    test(
      'ignores a candidate pair that is neither succeeded nor nominated',
      () {
        final counters = StatsCounters.fromReports([
          candidatePair(
            'pair',
            rttSeconds: 0.9,
            nominated: false,
            succeeded: false,
          ),
        ]);
        expect(counters.rttMs, isNull);
      },
    );

    StatsReport transport(String selectedPairId) => StatsReport(
      'transport',
      'transport',
      0,
      {'selectedCandidatePairId': selectedPairId},
    );

    test('reads RTT from the selected pair, not a stale relay after it', () {
      final counters = StatsCounters.fromReports([
        transport('wifi'),
        candidatePair('wifi', rttSeconds: 0.016),
        candidatePair('relay', rttSeconds: 0.420, nominated: false),
      ]);
      expect(counters.rttMs, 16);
    });

    test('without a transport report, reads the nominated pair', () {
      final counters = StatsCounters.fromReports([
        candidatePair('wifi', rttSeconds: 0.020),
        candidatePair('relay', rttSeconds: 0.420, nominated: false),
      ]);
      expect(counters.rttMs, 20);
    });

    test('a succeeded pair nobody selected or nominated gives no RTT', () {
      final counters = StatsCounters.fromReports([
        candidatePair('relay', rttSeconds: 0.420, nominated: false),
      ]);
      expect(counters.rttMs, isNull);
    });

    StatsCounters uplink(Map<String, UplinkCounters> streams) =>
        StatsCounters(uplinkStreams: streams);

    test('counts the loss the server reports, weighing each stream by the '
        'packets it sent', () {
      final sample =
          uplink({
            'audio': (fractionLost: 0, sent: 1150),
            'video': (fractionLost: 0.2, sent: 1450),
          }).linkSampleSince(
            uplink({
              'audio': (fractionLost: 0, sent: 1000),
              'video': (fractionLost: 0.2, sent: 1000),
            }),
            cameraSending: false,
          );
      expect(sample.lossFraction, closeTo(0.15, 1e-9));
    });

    test('a few packets sent say nothing about upload loss', () {
      final sample = uplink({'audio': (fractionLost: 0.5, sent: 1010)})
          .linkSampleSince(
            uplink({'audio': (fractionLost: 0.5, sent: 1000)}),
            cameraSending: false,
          );
      expect(sample.lossFraction, 0);
    });

    test('joins each server report to the stream it describes and drops '
        'reports for streams we no longer send', () {
      final counters = StatsCounters.fromReports([
        outboundRtp('out-audio', packetsSent: 1000),
        remoteInboundRtp('out-audio', 0.1),
        remoteInboundRtp('gone', 0.5),
      ]);
      expect(counters.uplinkStreams, {
        'out-audio': (fractionLost: 0.1, sent: 1000),
      });
    });

    test('the link sample is our upload loss and our round trip, never the '
        'loss on what reaches us', () {
      final before = StatsCounters.fromReports([
        inboundRtp('in', lost: 0, received: 1000),
        outboundRtp('out-audio', packetsSent: 1000),
        remoteInboundRtp('out-audio', 0.02),
        candidatePair('pair', rttSeconds: 0.040),
      ]);
      final after = StatsCounters.fromReports([
        inboundRtp('in', lost: 400, received: 1100),
        outboundRtp('out-audio', packetsSent: 1100),
        remoteInboundRtp('out-audio', 0.02),
        candidatePair('pair', rttSeconds: 0.040),
      ]);

      final sample = after.linkSampleSince(before, cameraSending: false);

      expect(sample.lossFraction, closeTo(0.02, 1e-9));
      expect(sample.rttMs, 40);
    });

    test('reads the upload estimate from the selected pair, not a stale '
        'relay', () {
      final counters = StatsCounters.fromReports([
        transport('wifi'),
        candidatePair('wifi', uploadBps: 180000),
        candidatePair('relay', uploadBps: 2000000, nominated: false),
      ]);

      expect(
        counters
            .linkSampleSince(counters, cameraSending: true)
            .uploadBandwidthBps,
        180000,
      );
    });

    test('with the camera off the estimate is not judged', () {
      final counters = StatsCounters.fromReports([
        transport('wifi'),
        candidatePair('wifi', uploadBps: 50000),
      ]);

      expect(
        counters
            .linkSampleSince(counters, cameraSending: false)
            .uploadBandwidthBps,
        isNull,
      );
    });
  });
}
