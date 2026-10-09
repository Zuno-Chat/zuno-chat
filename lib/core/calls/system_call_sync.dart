import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:matrix/matrix.dart' hide CallSession;

import '../matrix/room_title.dart';
import '../platform/platform_capabilities.dart';
import 'active_call_provider.dart';
import 'matrixrtc/call_session.dart';
import 'matrixrtc/call_summary_message.dart';
import 'models/call_engine_participant.dart';
import 'models/call_kind.dart';
import 'notifications/call_notification_service.dart';
import 'platform/system_call.dart';
import 'platform/system_ring.dart';

const emptyCallTimeout = Duration(seconds: 15);

final systemCallSyncProvider = Provider<void>((ref) {
  if (!ref.watch(platformCapabilitiesProvider).callKit) return;
  final systemCall = ref.watch(systemCallProvider);
  _SystemCallBinding? binding;

  void release(CallSession session) =>
      ref.read(activeCallProvider.notifier).clear(session);

  ref.listen<CallSession?>(activeCallProvider, (_, session) {
    if (identical(binding?.session, session)) return;
    binding?.abandon();
    binding = null;
    if (session == null) return;
    SystemRing.instance.clear(session.callId);
    binding = _SystemCallBinding(session, systemCall, onEnded: release);
  }, fireImmediately: true);

  final notifications = CallNotificationService.instance;
  final muteSub = notifications.onSystemMute.listen(
    (mute) => binding?.applySystemMute(mute),
  );
  final failedSub = notifications.onSystemCallFailed.listen(
    (callId) => binding?.fail(callId),
  );
  ref.onDispose(() {
    binding?.dispose();
    unawaited(muteSub.cancel());
    unawaited(failedSub.cancel());
  });
});

class _SystemCallBinding {
  _SystemCallBinding(this.session, this._systemCall, {required this.onEnded}) {
    _videoShown = session.kind == CallKind.video;
    _phaseSub = session.phaseStream.listen(_onPhase);
    _remoteJoinedSub = session.remoteJoinedStream.listen((_) => _connected());
    if (session.role == CallSessionRole.callee) {
      _timelineSub = session.room.client.onTimelineEvent.stream.listen(
        _onTimelineEvent,
      );
    }
    unawaited(_begin());
  }

  final CallSession session;
  final SystemCall _systemCall;
  final void Function(CallSession session) onEnded;

  StreamSubscription<CallSessionPhase>? _phaseSub;
  StreamSubscription<void>? _remoteJoinedSub;
  StreamSubscription<Event>? _timelineSub;
  StreamSubscription<List<CallEngineParticipant>>? _participantsSub;
  Timer? _emptyCallTimer;
  bool _muted = false;
  bool _videoShown = false;
  bool _connectedSent = false;
  bool _ended = false;

  String get _roomId => session.room.id;

  Future<void> _begin() async {
    final start = await _systemCall.begin(
      roomId: _roomId,
      callId: session.callId,
      title: roomTitle(session.room),
      isVideo: session.kind == CallKind.video,
    );
    if (_ended) return;
    if (start.muted) {
      await applySystemMute((callId: session.callId, muted: true));
    }
    if (session.everHadRemote) _connected();
    _followEngine();
    _onPhase(session.phase);
  }

  void _onPhase(CallSessionPhase phase) {
    if (_ended) return;
    if (phase == CallSessionPhase.active) _startEmptyCallTimer();
    if (phase == CallSessionPhase.ended) _end();
  }

  void _followEngine() {
    if (_ended) return;
    final engine = session.engine;
    _participantsSub = engine.participantsStream.listen(_onParticipants);
    _onParticipants(engine.participants);
  }

  void _startEmptyCallTimer() {
    if (session.role != CallSessionRole.callee || session.everHadRemote) return;
    if (_connectedSent || _emptyCallTimer != null) return;
    _emptyCallTimer = Timer(emptyCallTimeout, _endIfEmpty);
  }

  void _onParticipants(List<CallEngineParticipant> participants) {
    if (_ended) return;
    final local = participants.where((p) => p.isLocal).firstOrNull;
    if (local != null && local.audioMuted != _muted) {
      _muted = local.audioMuted;
      unawaited(
        _systemCall.setMuted(
          roomId: _roomId,
          callId: session.callId,
          muted: _muted,
        ),
      );
    }
    if (!_videoShown && participants.any((p) => p.videoEnabled)) {
      _videoShown = true;
      unawaited(
        _systemCall.upgradeToVideo(roomId: _roomId, callId: session.callId),
      );
    }
  }

  Future<void> applySystemMute(SystemMute mute) async {
    if (mute.callId != session.callId || _ended) return;
    _muted = mute.muted;
    await session.engine.setMicrophoneMuted(mute.muted);
    unawaited(session.refreshMembership());
  }

  void fail(String callId) {
    if (callId != session.callId || session.phase == CallSessionPhase.ended) {
      return;
    }
    session.failedMessage = callDidNotConnectMessage;
    session.endReason = CallEndReason.failed;
    unawaited(session.hangUp());
  }

  void _onTimelineEvent(Event event) {
    if (_ended || session.everHadRemote) return;
    if (event.room.id != _roomId) return;
    if (!isCallSummaryMessage(event.messageType)) return;
    if (event.content.tryGet<String>('call_id') != session.callId) return;
    unawaited(session.hangUp(summarized: true));
  }

  void _endIfEmpty() {
    if (_ended || session.everHadRemote) return;
    unawaited(session.hangUp());
  }

  void _connected() {
    if (_connectedSent || _ended) return;
    _connectedSent = true;
    _emptyCallTimer?.cancel();
    _emptyCallTimer = null;
    unawaited(_timelineSub?.cancel());
    _timelineSub = null;
    unawaited(_remoteJoinedSub?.cancel());
    _remoteJoinedSub = null;
    unawaited(_systemCall.connected(roomId: _roomId, callId: session.callId));
  }

  void _end() {
    final end = switch (session.endReason) {
      CallEndReason.missed => SystemCallEnd.unanswered,
      CallEndReason.failed => SystemCallEnd.failed,
      _ => SystemCallEnd.remoteEnded,
    };
    _close(end, byUser: session.endedByUser);
    onEnded(session);
  }

  void abandon() {
    if (!_ended) _close(SystemCallEnd.failed);
  }

  void _close(SystemCallEnd end, {bool byUser = false}) {
    dispose();
    unawaited(
      _systemCall.end(
        roomId: _roomId,
        callId: session.callId,
        end: end,
        byUser: byUser,
      ),
    );
  }

  void dispose() {
    _ended = true;
    _emptyCallTimer?.cancel();
    _emptyCallTimer = null;
    unawaited(_phaseSub?.cancel());
    unawaited(_remoteJoinedSub?.cancel());
    unawaited(_timelineSub?.cancel());
    unawaited(_participantsSub?.cancel());
    _phaseSub = null;
    _remoteJoinedSub = null;
    _timelineSub = null;
    _participantsSub = null;
  }
}
