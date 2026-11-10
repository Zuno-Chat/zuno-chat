import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/call_engine_status.dart';
import '../models/call_quality.dart';
import '../models/voip_participant_id.dart';
import 'webrtc_backend.dart';

enum MediaKind { audio, video }

enum VideoSlot { none, held, ready }

typedef CallSpec = ({String roomId, String callId});

typedef LocalSend = ({
  MediaStreamTrack microphone,
  MediaStreamTrack? camera,
  bool sendCamera,
});

abstract interface class CallConnectionOpener {
  Future<CallConnection> open(
    CallSpec spec,
    CallConnectionHost host, {
    bool rediscover = false,
  });
}

abstract interface class CallConnectionHost {
  WebRtcBackend get webRtc;
  LocalSend get localSend;
  bool get sendingCamera;
  List<RTCRtpEncoding> get videoEncodings;
  Future<void> publishLocalMedia(Future<bool> Function() publish);
  Future<void> adoptSender(MediaKind kind, RTCRtpSender sender);
  Future<void> adoptReceiver(
    VoipParticipantId id,
    MediaKind kind,
    RTCRtpReceiver receiver,
  );
  Future<void> dropReceiver(VoipParticipantId id, MediaKind kind);
  void setRemoteStream(
    VoipParticipantId id,
    MediaKind kind,
    MediaStream? stream,
  );
  Future<void> connectionReplaced(Future<void> Function() closeOld);
  void peerRating(VoipParticipantId id, CallQuality? rating);
  void reportStatus(CallEngineStatus status);
  void handleChanged();
  void remotesChanged();
}

abstract interface class CallConnection {
  Future<void> join();
  VideoSlot get videoSlot;
  Future<bool> showVideo(MediaStreamTrack? camera);
  RTCRtpSender? sender(MediaKind kind);
  List<RTCPeerConnection> get peerConnections;
  Map<String, Object?>? get handle;
  bool updateRemote(
    VoipParticipantId id,
    Map<String, Object?> fociInfo,
    Set<MediaKind> wanted, {
    required String? membershipEventId,
  });
  bool sendingMedia(VoipParticipantId id);
  void removeRemote(VoipParticipantId id);
  void observeStats(Iterable<StatsReport> reports);
  void sendRating(CallQuality rating);
  Future<void> close();
}
