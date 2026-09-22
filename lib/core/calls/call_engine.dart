import 'dart:typed_data';

import 'models/call_engine_participant.dart';
import 'models/call_engine_status.dart';
import 'models/call_kind.dart';
import 'models/call_quality.dart';
import 'models/voip_participant_id.dart';

abstract class CallEngine {
  CallEngineStatus get status;
  Stream<CallEngineStatus> get statusStream;

  List<CallEngineParticipant> get participants;
  Stream<List<CallEngineParticipant>> get participantsStream;

  CallKind get kind;
  CallQuality get quality;
  Stream<void> get localStateChangedStream;
  Map<String, Object?>? get localFociInfo;

  Future<void> join();
  Future<void> leave();
  Future<void> setMicrophoneMuted(bool muted);
  Future<void> setCameraEnabled(bool enabled);
  Future<void> switchCamera();
  Future<void> switchToVideo();
  Future<void> setEncryptionKey(Uint8List key);

  void updateRemoteParticipant(
    VoipParticipantId id,
    Map<String, Object?> fociInfo,
  );
  void removeRemoteParticipant(VoipParticipantId id);
  void dispose();
}
