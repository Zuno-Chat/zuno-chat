import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../errors/best_effort.dart';
import '../media/quality_report.dart';
import '../models/call_quality.dart';
import '../models/voip_participant_id.dart';

typedef _Subscription = ({String peerSession, int id, RTCDataChannel channel});

final class RatingsClaim {
  RatingsClaim._(this._peerSession);

  final String _peerSession;
}

class CloudflareQualityChannel {
  CloudflareQualityChannel({required this.onRating});

  final void Function(VoipParticipantId peer, CallQuality? rating) onRating;
  RTCDataChannel? _published;
  bool _opening = false;
  bool _givenUp = false;
  final Map<VoipParticipantId, _Subscription> _subscriptions = {};
  final Map<VoipParticipantId, RatingsClaim> _claims = {};
  final Map<VoipParticipantId, String> _failed = {};

  bool get isPublished => _published != null;

  bool claimPublish() {
    if (_givenUp || _opening || _published != null) return false;
    return _opening = true;
  }

  void publish(RTCDataChannel channel) {
    _opening = false;
    _published = channel;
  }

  void giveUp() {
    _opening = false;
    _givenUp = true;
  }

  void send(CallQuality quality) {
    final channel = _published;
    if (channel == null) return;
    unawaited(
      runBestEffort(
        () => channel.send(RTCDataChannelMessage(encodeQualityReport(quality))),
        label: 'send our call quality',
      ),
    );
  }

  RatingsClaim? claim(VoipParticipantId peer, String peerSession) {
    if (_subscriptions[peer]?.peerSession == peerSession ||
        _claims[peer]?._peerSession == peerSession ||
        _failed[peer] == peerSession) {
      return null;
    }
    return _claims[peer] = RatingsClaim._(peerSession);
  }

  void release(VoipParticipantId peer, RatingsClaim claim) {
    if (identical(_claims[peer], claim)) _claims.remove(peer);
  }

  bool fail(VoipParticipantId peer, String peerSession) {
    if (_failed[peer] == peerSession) return false;
    _failed[peer] = peerSession;
    return true;
  }

  void subscribe(
    VoipParticipantId peer, {
    required String peerSession,
    required int id,
    required RTCDataChannel channel,
  }) {
    channel.onMessage = (message) {
      if (message.isBinary) return;
      if (decodeQualityReport(message.text) case final rating?) {
        onRating(peer, rating);
      }
    };
    _subscriptions[peer] = (peerSession: peerSession, id: id, channel: channel);
  }

  int? drop(VoipParticipantId peer) {
    _failed.remove(peer);
    final subscription = _subscriptions.remove(peer);
    if (subscription == null) return null;
    unawaited(closeQualityChannel(subscription.channel));
    onRating(peer, null);
    return subscription.id;
  }

  Future<void> reset() async {
    final channels = [
      ?_published,
      for (final subscription in _subscriptions.values) subscription.channel,
    ];
    final peers = _subscriptions.keys.toList();
    _published = null;
    _opening = false;
    _subscriptions.clear();
    _claims.clear();
    _failed.clear();
    for (final peer in peers) {
      onRating(peer, null);
    }
    for (final channel in channels) {
      await closeQualityChannel(channel);
    }
  }
}

Future<void> closeQualityChannel(RTCDataChannel channel) {
  channel.onMessage = null;
  return runBestEffort(channel.close, label: 'close a quality channel');
}
