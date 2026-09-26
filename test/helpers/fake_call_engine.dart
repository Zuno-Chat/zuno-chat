import 'dart:async';
import 'dart:typed_data';

import 'package:zuno/core/calls/call_engine.dart';
import 'package:zuno/core/calls/models/call_engine_participant.dart';
import 'package:zuno/core/calls/models/call_engine_status.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/models/call_quality.dart';
import 'package:zuno/core/calls/models/voip_participant_id.dart';

class FakeCallEngine implements CallEngine {
  FakeCallEngine({
    this.failSetEncryptionKey = false,
    this.failJoin = false,
    this.joinError,
    this.joinGate,
    this.kind = CallKind.voice,
  });

  final bool failSetEncryptionKey;
  final bool failJoin;
  final Completer<void>? joinGate;

  final Object? joinError;

  bool joined = false;
  Uint8List? appliedKey;

  @override
  CallEngineStatus status = CallEngineStatus.connected;

  final statusController = StreamController<CallEngineStatus>.broadcast();

  @override
  Stream<CallEngineStatus> get statusStream => statusController.stream;

  void setStatus(CallEngineStatus next) {
    status = next;
    statusController.add(next);
  }

  @override
  List<CallEngineParticipant> participants = const [];

  final participantsController =
      StreamController<List<CallEngineParticipant>>.broadcast();

  @override
  Stream<List<CallEngineParticipant>> get participantsStream =>
      participantsController.stream;

  void setParticipants(List<CallEngineParticipant> next) {
    participants = next;
    participantsController.add(next);
  }

  @override
  final CallKind kind;

  @override
  Future<void> join() async {
    await joinGate?.future;
    if (failJoin) {
      throw joinError ?? StateError('engine failed to connect to the SFU');
    }
    joined = true;
  }

  int leaveCalls = 0;
  int disposeCalls = 0;

  @override
  Future<void> leave() async {
    if (disposeCalls > 0) {
      throw StateError('Cannot add new events after calling close');
    }
    leaveCalls++;
    joined = false;
  }

  final microphoneMutedRequests = <bool>[];
  final cameraEnabledRequests = <bool>[];
  int switchCameraCalls = 0;
  int switchToVideoCalls = 0;

  @override
  Future<void> setMicrophoneMuted(bool muted) async =>
      microphoneMutedRequests.add(muted);
  @override
  Future<void> setCameraEnabled(bool enabled) async =>
      cameraEnabledRequests.add(enabled);
  @override
  Future<void> switchCamera() async => switchCameraCalls++;
  @override
  Future<void> switchToVideo() async => switchToVideoCalls++;

  bool micMuted = false;

  final localStateController = StreamController<void>.broadcast();

  @override
  Stream<void> get localStateChangedStream => localStateController.stream;

  @override
  Map<String, Object?>? get localFociInfo => joined
      ? {
          'sessionId': 'fake-session',
          'tracks': const {'audio': 'audio'},
          'audioMuted': micMuted,
          'encrypted': appliedKey != null,
        }
      : null;

  int updateRemoteParticipantCalls = 0;

  @override
  void updateRemoteParticipant(
    VoipParticipantId id,
    Map<String, Object?> fociInfo,
  ) {
    updateRemoteParticipantCalls++;
  }

  @override
  void removeRemoteParticipant(VoipParticipantId id) {}

  @override
  Future<void> setEncryptionKey(Uint8List key) async {
    if (failSetEncryptionKey) {
      throw StateError(
        'frame cryptor rejected the key — unable to encrypt packets',
      );
    }
    appliedKey = key;
    localStateController.add(null);
  }

  @override
  CallQuality quality = CallQuality.good;

  @override
  void dispose() {
    disposeCalls++;
    localStateController.close();
    statusController.close();
    participantsController.close();
  }
}
