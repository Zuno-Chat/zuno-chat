import 'dart:math' show max, min;

import 'package:flutter_webrtc/flutter_webrtc.dart' show StatsReport;

import '../models/call_quality.dart';

class QualitySample {
  final double lossFraction;
  final double? rttMs;
  final double? uploadBandwidthBps;

  const QualitySample({
    required this.lossFraction,
    this.rttMs,
    this.uploadBandwidthBps,
  });
}

typedef UplinkCounters = ({double fractionLost, int sent});

class StatsCounters {
  final Map<String, UplinkCounters> uplinkStreams;
  final double? rttMs;
  final double? uploadBandwidthBps;
  final bool sends;

  const StatsCounters({
    this.uplinkStreams = const {},
    this.rttMs,
    this.uploadBandwidthBps,
    this.sends = false,
  });

  factory StatsCounters.fromReports(Iterable<StatsReport> reports) {
    final pairs = <String, StatsReport>{};
    final packetsSent = <String, int>{};
    final serverLoss = <String, double>{};
    String? selectedPairId;
    var sends = false;
    for (final report in reports) {
      switch (report.type) {
        case 'outbound-rtp':
          sends = true;
          if (report.values['packetsSent'] case final num sent) {
            packetsSent[report.id] = sent.toInt();
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
    final estimate = livePair?.values['availableOutgoingBitrate'];
    return StatsCounters(
      uplinkStreams: {
        for (final MapEntry(key: id, value: fraction) in serverLoss.entries)
          if (packetsSent[id] case final sent?)
            id: (fractionLost: fraction, sent: sent),
      },
      rttMs: rttSeconds is num ? rttSeconds * 1000.0 : null,
      uploadBandwidthBps: estimate is num ? estimate.toDouble() : null,
      sends: sends,
    );
  }

  factory StatsCounters.merged(List<StatsCounters> perPeerConnection) {
    final rtts = [for (final pc in perPeerConnection) ?pc.rttMs];
    final estimates = [
      for (final pc in perPeerConnection)
        if (pc.sends) ?pc.uploadBandwidthBps,
    ];
    return StatsCounters(
      uplinkStreams: {
        for (final (index, pc) in perPeerConnection.indexed)
          for (final MapEntry(key: id, value: counters)
              in pc.uplinkStreams.entries)
            '$index/$id': counters,
      },
      rttMs: rtts.isEmpty ? null : rtts.reduce(max),
      uploadBandwidthBps: estimates.isEmpty ? null : estimates.reduce(min),
      sends: perPeerConnection.any((pc) => pc.sends),
    );
  }

  static const minPacketsToJudgeLoss = 60;

  QualitySample linkSampleSince(
    StatsCounters previous, {
    required bool cameraSending,
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
    return QualitySample(
      lossFraction: _judgedLoss(lostWeight, deltaSent),
      rttMs: rttMs,
      uploadBandwidthBps: cameraSending ? uploadBandwidthBps : null,
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
  static const exitDegradedVideoBps = 400000;
  static const exitPoorVideoBps = 160000;
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
    final video = sample.uploadBandwidthBps ?? double.infinity;
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
    final video = sample.uploadBandwidthBps ?? double.infinity;
    return switch (tier) {
      CallQuality.poor =>
        sample.lossFraction < exitPoorLoss &&
            rtt < exitPoorRttMs &&
            video >= exitPoorVideoBps,
      CallQuality.degraded =>
        sample.lossFraction < exitDegradedLoss &&
            rtt < exitDegradedRttMs &&
            video >= exitDegradedVideoBps,
      CallQuality.good => false,
    };
  }
}

const startBitrateKbps = 500;
