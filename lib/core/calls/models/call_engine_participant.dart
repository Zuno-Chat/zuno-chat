import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'voip_participant_id.dart';

class CallEngineParticipant {
  final VoipParticipantId id;
  final bool isLocal;
  final MediaStream? audioStream;
  final MediaStream? videoStream;
  final bool audioMuted;
  final bool videoEnabled;
  final bool encrypted;
  final bool lowBandwidth;
  final bool frontCamera;

  const CallEngineParticipant({
    required this.id,
    required this.isLocal,
    this.audioStream,
    this.videoStream,
    this.audioMuted = false,
    this.videoEnabled = false,
    this.encrypted = false,
    this.lowBandwidth = false,
    this.frontCamera = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallEngineParticipant &&
          id == other.id &&
          isLocal == other.isLocal &&
          audioStream?.id == other.audioStream?.id &&
          videoStream?.id == other.videoStream?.id &&
          audioMuted == other.audioMuted &&
          videoEnabled == other.videoEnabled &&
          encrypted == other.encrypted &&
          lowBandwidth == other.lowBandwidth &&
          frontCamera == other.frontCamera;

  @override
  int get hashCode => Object.hash(
    id,
    isLocal,
    audioStream?.id,
    videoStream?.id,
    audioMuted,
    videoEnabled,
    encrypted,
    lowBandwidth,
    frontCamera,
  );
}
