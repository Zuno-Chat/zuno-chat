import 'dart:math' show max;

import 'package:flutter_webrtc/flutter_webrtc.dart'
    show
        RTCDegradationPreference,
        RTCRtpParameters,
        RTCRtpEncoding,
        StatsReport;

import '../models/call_quality.dart';

class QualitySample {
  final double lossFraction;
  final double? rttMs;
  final double? linkLimitedVideoBps;

  const QualitySample({
    required this.lossFraction,
    this.rttMs,
    this.linkLimitedVideoBps,
  });
}

typedef StreamCounters = ({int lost, int received});

typedef UplinkCounters = ({double fractionLost, int sent});

class StatsCounters {
  final Map<String, StreamCounters> streams;
  final Map<String, UplinkCounters> uplinkStreams;
  final double? rttMs;
  final double? videoTargetBps;

  const StatsCounters({
    this.streams = const {},
    this.uplinkStreams = const {},
    this.rttMs,
    this.videoTargetBps,
  });

  int get packetsLost => streams.values.fold(0, (sum, s) => sum + s.lost);

  int get packetsReceived =>
      streams.values.fold(0, (sum, s) => sum + s.received);

  factory StatsCounters.fromReports(Iterable<StatsReport> reports) {
    final streams = <String, StreamCounters>{};
    final pairs = <String, StatsReport>{};
    final packetsSent = <String, int>{};
    final serverLoss = <String, double>{};
    String? selectedPairId;
    double? videoTargetBps;
    for (final report in reports) {
      switch (report.type) {
        case 'inbound-rtp':
          final lost = report.values['packetsLost'];
          final received = report.values['packetsReceived'];
          streams[report.id] = (
            lost: lost is num ? lost.toInt() : 0,
            received: received is num ? received.toInt() : 0,
          );
        case 'outbound-rtp':
          if (report.values['packetsSent'] case final num sent) {
            packetsSent[report.id] = sent.toInt();
          }
          if (report.values case {
            'kind': 'video',
            'targetBitrate': final num target,
          }) {
            videoTargetBps = target.toDouble();
          }
        case 'remote-inbound-rtp':
          if ((report.values['localId'], report.values['fractionLost']) case (
            final String localId,
            final num fraction,
          )) {
            serverLoss[localId] = fraction.toDouble();
          }
        case 'candidate-pair':
          pairs[report.id] = report;
        case 'transport':
          if (report.values['selectedCandidatePairId'] case final String id) {
            selectedPairId = id;
          }
      }
    }
    final livePair =
        pairs[selectedPairId] ??
        pairs.values
            .where(
              (pair) =>
                  pair.values['nominated'] == true &&
                  pair.values['state'] == 'succeeded',
            )
            .firstOrNull;
    final rttSeconds = livePair?.values['currentRoundTripTime'];
    return StatsCounters(
      streams: streams,
      uplinkStreams: {
        for (final MapEntry(key: id, value: fraction) in serverLoss.entries)
          if (packetsSent[id] case final sent?)
            id: (fractionLost: fraction, sent: sent),
      },
      rttMs: rttSeconds is num ? rttSeconds * 1000.0 : null,
      videoTargetBps: videoTargetBps,
    );
  }

  static const minPacketsToJudgeLoss = 60;
  static const belowCapToJudgeLink = 0.9;

  QualitySample downlinkSampleSince(StatsCounters previous) {
    var deltaLost = 0;
    var deltaReceived = 0;
    for (final MapEntry(key: id, value: now) in streams.entries) {
      final before = previous.streams[id];
      if (before == null) continue;
      deltaLost += max(0, now.lost - before.lost);
      deltaReceived += max(0, now.received - before.received);
    }
    return QualitySample(
      lossFraction: _judgedLoss(deltaLost, deltaLost + deltaReceived),
      rttMs: rttMs,
    );
  }

  QualitySample uplinkSampleSince(
    StatsCounters previous, {
    required int? videoCapBps,
  }) {
    var lostWeight = 0.0;
    var deltaSent = 0;
    for (final MapEntry(key: id, value: now) in uplinkStreams.entries) {
      final before = previous.uplinkStreams[id];
      if (before == null) continue;
      final sent = max(0, now.sent - before.sent);
      lostWeight += now.fractionLost * sent;
      deltaSent += sent;
    }
    final target = videoTargetBps;
    return QualitySample(
      lossFraction: _judgedLoss(lostWeight, deltaSent),
      linkLimitedVideoBps:
          videoCapBps != null &&
              target != null &&
              target < videoCapBps * belowCapToJudgeLink
          ? target
          : null,
    );
  }

  static double _judgedLoss(num lost, int total) =>
      total < minPacketsToJudgeLoss ? 0 : lost / total;
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
  static const enterDegradedVideoBps = 300000;
  static const enterPoorVideoBps = 120000;
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
    final video = sample.linkLimitedVideoBps ?? double.infinity;
    if (sample.lossFraction >= enterPoorLoss ||
        rtt >= enterPoorRttMs ||
        video < enterPoorVideoBps) {
      return CallQuality.poor;
    }
    if (sample.lossFraction >= enterDegradedLoss ||
        rtt >= enterDegradedRttMs ||
        video < enterDegradedVideoBps) {
      return CallQuality.degraded;
    }
    return CallQuality.good;
  }

  static bool _clearsExitOf(CallQuality tier, QualitySample sample) {
    final rtt = sample.rttMs ?? 0;
    final linkHoldsVideo = sample.linkLimitedVideoBps != null;
    return switch (tier) {
      CallQuality.poor =>
        sample.lossFraction < exitPoorLoss &&
            rtt < exitPoorRttMs &&
            !linkHoldsVideo,
      CallQuality.degraded =>
        sample.lossFraction < exitDegradedLoss &&
            rtt < exitDegradedRttMs &&
            !linkHoldsVideo,
      CallQuality.good => false,
    };
  }
}

typedef VideoEncodingLimits = ({
  double scaleResolutionDownBy,
  int maxFramerate,
  int maxBitrate,
});

const startBitrateKbps = 500;

({int width, int height}) captureSizeFor({required bool lowDataMode}) =>
    lowDataMode ? (width: 640, height: 360) : (width: 854, height: 480);

VideoEncodingLimits videoEncodingFor(
  CallQuality quality, {
  required bool lowDataMode,
}) {
  final capturedHeight = captureSizeFor(lowDataMode: lowDataMode).height;
  return switch (quality) {
    CallQuality.good => (
      scaleResolutionDownBy: 1.0,
      maxFramerate: 30,
      maxBitrate: lowDataMode ? 500000 : 950000,
    ),
    CallQuality.degraded => (
      scaleResolutionDownBy: capturedHeight / 240,
      maxFramerate: 30,
      maxBitrate: 400000,
    ),
    CallQuality.poor => (
      scaleResolutionDownBy: capturedHeight / 180,
      maxFramerate: 15,
      maxBitrate: 150000,
    ),
  };
}

CallQuality combineQuality({
  required CallQuality local,
  required bool anyRemoteLowBandwidth,
}) => local.worse(
  anyRemoteLowBandwidth ? CallQuality.degraded : CallQuality.good,
);

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
  params
    ..encodings = [first, ...encodings.skip(1)]
    ..degradationPreference = RTCDegradationPreference.MAINTAIN_FRAMERATE;
  return params;
}
