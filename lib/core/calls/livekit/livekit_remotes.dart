import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter_webrtc/flutter_webrtc.dart'
    show MediaStream, RTCRtpReceiver;

import '../media/call_connection.dart';
import '../models/voip_participant_id.dart';
import 'proto/livekit_models.pb.dart';

typedef LiveKitStreamId = ({String participantSid, String trackSid});

const _separator = '|';
const _trackSidPrefix = 'TR_';

LiveKitStreamId? parseLiveKitStreamId(String streamId, String? trackId) {
  final at = streamId.indexOf(_separator);
  if (at <= 0) return null;
  final packed = streamId.substring(at + 1);
  final trackSid = packed.startsWith(_trackSidPrefix) ? packed : trackId;
  if (trackSid == null || trackSid.isEmpty) return null;
  return (participantSid: streamId.substring(0, at), trackSid: trackSid);
}

class LiveKitArrival {
  const LiveKitArrival({
    required this.participantSid,
    required this.trackSid,
    required this.receiver,
    required this.stream,
  });

  final String participantSid;
  final String trackSid;
  final RTCRtpReceiver receiver;
  final MediaStream stream;
}

typedef LiveKitSlot = ({VoipParticipantId id, MediaKind kind});

typedef LiveKitAttachment = ({LiveKitSlot slot, LiveKitArrival arrival});

typedef LiveKitSubscriptionChanges = ({
  List<String> subscribe,
  List<String> unsubscribe,
});

typedef LiveKitParticipantsUpdate = ({
  bool sendingChanged,
  Set<VoipParticipantId> departed,
});

typedef _Member = ({String identity, Set<MediaKind> wanted});

typedef _Wanted = ({LiveKitSlot slot, String participantSid});

extension type const LiveKitWanted._(Map<String, _Wanted> _tracks) {}

MediaKind? _kindOf(TrackType type) => switch (type) {
  TrackType.AUDIO => MediaKind.audio,
  TrackType.VIDEO => MediaKind.video,
  _ => null,
};

class LiveKitRemotes {
  final Map<String, ParticipantInfo> _participants = {};
  final Map<VoipParticipantId, _Member> _members = {};
  final Set<String> _subscribed = {};
  final Set<String> _unsubscribedSinceSync = {};
  final Map<String, LiveKitArrival> _arrivals = {};
  final Map<LiveKitSlot, LiveKitArrival> _attached = {};
  final List<LiveKitSlot> _released = [];

  LiveKitParticipantsUpdate updateParticipants(
    Iterable<ParticipantInfo> infos, {
    required String ownIdentity,
  }) {
    final sendingBefore = _sending();
    final gone = <String>{};
    for (final info in infos) {
      if (info.identity.isEmpty || info.identity == ownIdentity) continue;
      final known = _participants[info.identity];
      final sameSid = known != null && known.sid == info.sid;
      if (info.state == ParticipantInfo_State.DISCONNECTED) {
        _forgetArrivalsOf(info.sid);
        if (sameSid) {
          _participants.remove(info.identity);
          gone.add(info.identity);
        }
        continue;
      }
      if (sameSid && info.version < known.version) continue;
      if (known != null && !sameSid) {
        if (info.joinedAtMs < known.joinedAtMs) continue;
        _forgetArrivalsOf(known.sid);
        gone.add(info.identity);
      }
      _participants[info.identity] = info;
      _forgetArrivalsOfUnpublished(info);
    }
    return (
      sendingChanged: !mapEquals(sendingBefore, _sending()),
      departed: {
        for (final MapEntry(key: id, value: member) in _members.entries)
          if (gone.contains(member.identity)) id,
      },
    );
  }

  void setMember(
    VoipParticipantId id,
    String identity,
    Set<MediaKind> wanted,
  ) => _members[id] = (identity: identity, wanted: Set.unmodifiable(wanted));

  void removeMember(VoipParticipantId id) => _members.remove(id);

  bool hasMember(VoipParticipantId id) => _members.containsKey(id);

  Iterable<VoipParticipantId> get members => _members.keys;

  VoipParticipantId? memberWith(String identity) {
    for (final MapEntry(key: id, value: member) in _members.entries) {
      if (member.identity == identity) return id;
    }
    return null;
  }

  bool sendingMedia(VoipParticipantId id) {
    final member = _members[id];
    if (member == null) return false;
    return _participants[member.identity]?.tracks.isNotEmpty ?? false;
  }

  void arrived(LiveKitArrival arrival) {
    bool sameReceiver(LiveKitArrival a) =>
        a.receiver.receiverId == arrival.receiver.receiverId;
    _arrivals.removeWhere((_, a) => sameReceiver(a));
    _release(sameReceiver);
    _arrivals[arrival.trackSid] = arrival;
  }

  void departed(String trackSid) {
    _arrivals.remove(trackSid);
    _release((a) => a.trackSid == trackSid);
  }

  void _release(bool Function(LiveKitArrival arrival) test) {
    _attached.removeWhere((slot, arrival) {
      if (!test(arrival)) return false;
      _released.add(slot);
      return true;
    });
  }

  LiveKitSubscriptionChanges subscriptionChanges(LiveKitWanted wanted) {
    final sids = wanted._tracks.keys;
    return (
      subscribe: [
        for (final sid in sids)
          if (!_subscribed.contains(sid)) sid,
      ],
      unsubscribe: [
        for (final sid in _subscribed)
          if (!wanted._tracks.containsKey(sid)) sid,
      ],
    );
  }

  void subscriptionsSent(List<String> sids, {required bool subscribe}) {
    if (subscribe) {
      _subscribed.addAll(sids);
      _unsubscribedSinceSync.removeAll(sids);
    } else {
      _subscribed.removeAll(sids);
      _unsubscribedSinceSync.addAll(sids);
    }
  }

  List<String> resync() {
    final sids = wanted()._tracks.keys.toList();
    _subscribed
      ..addAll(_unsubscribedSinceSync)
      ..addAll(sids);
    _unsubscribedSinceSync.clear();
    return sids;
  }

  ({List<LiveKitSlot> detach, List<LiveKitAttachment> attach}) attachments(
    LiveKitWanted wanted,
  ) {
    final detach = [
      ..._released,
      for (final MapEntry(key: slot, value: arrival) in _attached.entries)
        if (wanted._tracks[arrival.trackSid] !=
            (slot: slot, participantSid: arrival.participantSid))
          slot,
    ];
    _released.clear();
    for (final slot in detach) {
      if (_attached.remove(slot) case final arrival?) {
        _arrivals.putIfAbsent(arrival.trackSid, () => arrival);
      }
    }
    final attach = <LiveKitAttachment>[];
    for (final arrival in _arrivals.values.toList()) {
      final owner = wanted._tracks[arrival.trackSid];
      if (owner == null || owner.participantSid != arrival.participantSid) {
        continue;
      }
      _arrivals.remove(arrival.trackSid);
      if (_attached.containsKey(owner.slot)) detach.add(owner.slot);
      _attached[owner.slot] = arrival;
      attach.add((slot: owner.slot, arrival: arrival));
    }
    return (detach: detach, attach: attach);
  }

  bool isAttached(LiveKitSlot slot, LiveKitArrival arrival) =>
      identical(_attached[slot], arrival);

  void resetSession() {
    _participants.clear();
    _subscribed.clear();
    _unsubscribedSinceSync.clear();
    _arrivals.clear();
    _attached.clear();
    _released.clear();
  }

  void clear() {
    resetSession();
    _members.clear();
  }

  LiveKitWanted wanted() => LiveKitWanted._({
    for (final MapEntry(key: id, value: member) in _members.entries)
      if (_participants[member.identity] case final participant?)
        for (final track in participant.tracks)
          if (_kindOf(track.type) case final kind?
              when member.wanted.contains(kind) &&
                  track.encryption == Encryption_Type.GCM)
            track.sid: (
              slot: (id: id, kind: kind),
              participantSid: participant.sid,
            ),
  });

  Map<VoipParticipantId, bool> _sending() => {
    for (final id in _members.keys) id: sendingMedia(id),
  };

  void _forgetArrivalsOf(String participantSid) =>
      _arrivals.removeWhere((_, a) => a.participantSid == participantSid);

  void _forgetArrivalsOfUnpublished(ParticipantInfo info) {
    final published = {for (final track in info.tracks) track.sid};
    _arrivals.removeWhere(
      (sid, a) => a.participantSid == info.sid && !published.contains(sid),
    );
  }
}
