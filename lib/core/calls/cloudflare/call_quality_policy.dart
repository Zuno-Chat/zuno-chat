import 'dart:math' show max;

import 'package:flutter_webrtc/flutter_webrtc.dart'
    show RTCRtpParameters, RTCRtpEncoding, StatsReport;

import '../models/call_quality.dart';

class QualitySample {
  final double lossFraction;
  final double? rttMs;

  const QualitySample({required this.lossFraction, this.rttMs});
}

class StatsCounters {
  final int packetsLost;
  final int packetsReceived;
  final double? rttMs;

  const StatsCounters({
    required this.packetsLost,
    required this.packetsReceived,
    this.rttMs,
  });

  factory StatsCounters.fromReports(Iterable<StatsReport> reports) {
    var lost = 0;
    var received = 0;
    double? rttMs;
    for (final report in reports) {
      if (report.type == 'inbound-rtp') {
        if (report.values['packetsLost'] case final num n) lost += n.toInt();
        if (report.values['packetsReceived'] case final num n) {
          received += n.toInt();
        }
      } else if (report.type == 'candidate-pair' &&
          (report.values['state'] == 'succeeded' ||
              report.values['nominated'] == true)) {
        if (report.values['currentRoundTripTime'] case final num seconds) {
          rttMs = seconds * 1000;
        }
      }
    }
    return StatsCounters(
      packetsLost: lost,
      packetsReceived: received,
      rttMs: rttMs,
    );
  }

  QualitySample sampleSince(StatsCounters previous) {
    final deltaLost = max(0, packetsLost - previous.packetsLost);
    final deltaReceived = max(0, packetsReceived - previous.packetsReceived);
    final total = deltaLost + deltaReceived;
    return QualitySample(
      lossFraction: total == 0 ? 0 : deltaLost / total,
      rttMs: rttMs,
    );
  }
}

class CallQualityClassifier {
  static const enterDegradedLoss = 0.05;
  static const enterDegradedRttMs = 350.0;
  static const enterPoorLoss = 0.12;
  static const enterPoorRttMs = 700.0;
  static const exitDegradedLoss = 0.03;
  static const exitDegradedRttMs = 250.0;
  static const exitPoorLoss = 0.08;
  static const exitPoorRttMs = 500.0;
  static const samplesToWorsen = 2;
  static const samplesToRecover = 4;

  CallQuality _current = CallQuality.good;
  int _worseStreak = 0;
  int _betterStreak = 0;

  CallQuality get current => _current;

  CallQuality? observe(QualitySample sample) {
    final target = _tierEnteredBy(sample);
    if (target.index < _current.index) {
      _worseStreak++;
      _betterStreak = 0;
      if (_worseStreak < samplesToWorsen) return null;
      _reset();
      return _current = target;
    }
    if (_current != CallQuality.good && _clearsExitOf(_current, sample)) {
      _betterStreak++;
      _worseStreak = 0;
      if (_betterStreak < samplesToRecover) return null;
      _reset();
      return _current = CallQuality.values[_current.index + 1];
    }
    _reset();
    return null;
  }

  void _reset() {
    _worseStreak = 0;
    _betterStreak = 0;
  }

  static CallQuality _tierEnteredBy(QualitySample sample) {
    final rtt = sample.rttMs ?? 0;
    if (sample.lossFraction >= enterPoorLoss || rtt >= enterPoorRttMs) {
      return CallQuality.poor;
    }
    if (sample.lossFraction >= enterDegradedLoss || rtt >= enterDegradedRttMs) {
      return CallQuality.degraded;
    }
    return CallQuality.good;
  }

  static bool _clearsExitOf(CallQuality tier, QualitySample sample) {
    final rtt = sample.rttMs ?? 0;
    return switch (tier) {
      CallQuality.poor =>
        sample.lossFraction < exitPoorLoss && rtt < exitPoorRttMs,
      CallQuality.degraded =>
        sample.lossFraction < exitDegradedLoss && rtt < exitDegradedRttMs,
      CallQuality.good => false,
    };
  }
}

typedef VideoEncodingLimits = ({
  double scaleResolutionDownBy,
  int maxFramerate,
  int maxBitrate,
});

VideoEncodingLimits videoEncodingFor(
  CallQuality quality, {
  required bool lowDataMode,
}) => switch (quality) {
  CallQuality.good => (
    scaleResolutionDownBy: 1.0,
    maxFramerate: lowDataMode ? 24 : 30,
    maxBitrate: lowDataMode ? 500000 : 800000,
  ),
  CallQuality.degraded => (
    scaleResolutionDownBy: 2.0,
    maxFramerate: 15,
    maxBitrate: 300000,
  ),
  CallQuality.poor => (
    scaleResolutionDownBy: 2.0,
    maxFramerate: 10,
    maxBitrate: 150000,
  ),
};

CallQuality combineQuality({
  required CallQuality local,
  required bool anyRemoteLowBandwidth,
}) => anyRemoteLowBandwidth && local == CallQuality.good
    ? CallQuality.degraded
    : local;

RTCRtpParameters applyVideoEncodingLimits(
  RTCRtpParameters params,
  VideoEncodingLimits limits,
) {
  final encodings = params.encodings ?? [];
  final first = encodings.isNotEmpty ? encodings.first : RTCRtpEncoding();
  first
    ..scaleResolutionDownBy = limits.scaleResolutionDownBy
    ..maxFramerate = limits.maxFramerate
    ..maxBitrate = limits.maxBitrate;
  params.encodings = [first, ...encodings.skip(1)];
  return params;
}
