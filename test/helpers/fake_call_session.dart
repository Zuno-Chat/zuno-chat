import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import 'package:zuno/core/calls/matrixrtc/call_session.dart';
import 'package:zuno/core/calls/models/call_engine_participant.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/models/voip_participant_id.dart';

import 'fake_call_engine.dart';
import 'fake_matrix.dart';

class FakeCallSession implements CallSession {
  FakeCallSession({
    required this.room,
    required this.kind,
    this.role = CallSessionRole.callee,
    this._phase = CallSessionPhase.connecting,
  }) : engine = FakeCallEngine(kind: kind);

  @override
  final Room room;
  @override
  CallKind kind;
  @override
  final CallSessionRole role;
  @override
  final FakeCallEngine engine;
  @override
  String get callId => 'call-1';

  CallSessionPhase _phase;
  final _phases = StreamController<CallSessionPhase>.broadcast();
  final _remoteJoined = StreamController<void>.broadcast();

  @override
  CallSessionPhase get phase => _phase;
  @override
  Stream<CallSessionPhase> get phaseStream => _phases.stream;
  @override
  Stream<void> get remoteJoinedStream => _remoteJoined.stream;

  @override
  bool everHadRemote = false;
  @override
  CallEndReason? endReason;
  @override
  String? failedMessage;

  bool microphoneGranted = true;
  int membershipRefreshes = 0;
  final hangUpsByUser = <bool>[];
  final hangUpsSummarized = <bool>[];

  int get hangUps => hangUpsByUser.length;

  @override
  Future<void> ensurePermissions() async {
    if (!microphoneGranted) throw StateError('Microphone permission denied');
  }

  @override
  Future<void> refreshMembership() async => membershipRefreshes++;

  @override
  Future<void> hangUp({bool byUser = false, bool summarized = false}) async {
    hangUpsByUser.add(byUser);
    hangUpsSummarized.add(summarized);
  }

  @override
  bool get endedByUser => hangUpsByUser.firstOrNull ?? false;

  final wantedMutes = <bool>[];

  @override
  Future<void> setMicrophoneMutedWhenReady(bool muted) async {
    wantedMutes.add(muted);
    if (_phase == CallSessionPhase.active) {
      await engine.setMicrophoneMuted(muted);
    }
  }

  void moveTo(CallSessionPhase next) {
    _phase = next;
    _phases.add(next);
  }

  void remoteJoins() {
    everHadRemote = true;
    _remoteJoined.add(null);
  }

  void end({CallEndReason reason = CallEndReason.hungUp, String? message}) {
    endReason = reason;
    failedMessage = message;
    moveTo(CallSessionPhase.ended);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMediaStream extends MediaStream {
  FakeMediaStream(String id) : super(id, 'local');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CallEngineParticipant localParticipant({
  bool muted = false,
  bool camera = false,
}) => CallEngineParticipant(
  id: const VoipParticipantId(userId: 'local', deviceId: 'local'),
  isLocal: true,
  audioMuted: muted,
  videoEnabled: camera,
  videoStream: camera ? FakeMediaStream('local-video') : null,
  encrypted: true,
);

CallEngineParticipant remoteParticipant({
  String userId = '@ann:example.org',
  bool camera = false,
}) => CallEngineParticipant(
  id: VoipParticipantId(userId: userId, deviceId: 'ANN'),
  isLocal: false,
  videoEnabled: camera,
  videoStream: camera ? FakeMediaStream('$userId-video') : null,
  encrypted: true,
);

Room buildCallRoom() {
  final room = buildTestRoom(buildTestClient(userId: '@me:example.org'));
  room.setState(
    StrippedStateEvent(
      type: EventTypes.RoomName,
      senderId: '@me:example.org',
      stateKey: '',
      content: {'name': 'Weekend hike'},
    ),
  );
  for (final (userId, name) in [
    ('@me:example.org', 'Me'),
    ('@ann:example.org', 'Ann'),
  ]) {
    room.setState(
      StrippedStateEvent(
        type: EventTypes.RoomMember,
        senderId: userId,
        stateKey: userId,
        content: {'membership': 'join', 'displayname': name},
      ),
    );
  }
  return room;
}
