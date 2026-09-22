import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:matrix/matrix.dart' hide CallSession;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/calls/active_call_provider.dart';
import '../../../core/calls/matrixrtc/call_session.dart';
import '../../../core/calls/models/call_engine_participant.dart';
import '../../../core/calls/models/call_engine_status.dart';
import '../../../core/calls/models/call_kind.dart';
import '../../../core/calls/models/call_quality.dart';
import '../../../core/calls/models/voip_participant_id.dart';
import '../../../core/calls/notifications/call_notification_service.dart';
import '../../../core/matrix/room_title.dart';
import '../../../core/notifications/notification_sound_player.dart';
import '../../../core/ui/zuno_theme.dart';
import 'call_picture_in_picture.dart';
import 'call_proximity.dart';
import 'call_view.dart';
import 'participant_tile.dart';

class CallPage extends ConsumerStatefulWidget {
  final CallSession session;

  const CallPage({required this.session, super.key});

  @override
  ConsumerState<CallPage> createState() => _CallPageState();
}

class _CallPageState extends ConsumerState<CallPage> {
  CallSession get session => widget.session;

  StreamSubscription<CallSessionPhase>? _phaseSub;
  StreamSubscription<void>? _remoteJoinedSub;
  StreamSubscription<List<CallEngineParticipant>>? _participantsSub;
  StreamSubscription<CallEngineStatus>? _statusSub;
  StreamSubscription<void>? _localStateSub;
  CallEngineStatus? _engineStatus;
  final Map<VoipParticipantId, RTCVideoRenderer> _renderers = {};
  List<CallEngineParticipant> _participants = [];

  bool _speakerOn = false;
  bool _finished = false;
  DateTime? _talkingSince;
  ({bool eligible, int width, int height})? _sentPictureInPicture;
  bool? _sentProximityScreenOff;

  @override
  void initState() {
    super.initState();
    _phaseSub = session.phaseStream.listen(_onPhase);
    _remoteJoinedSub = session.remoteJoinedStream.listen((_) {
      _syncRingback();
    });
    _syncRingback();
    if (session.phase == CallSessionPhase.ended) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_finish()));
      return;
    }
    _init();
  }

  void _syncPictureInPicture() {
    if (!mounted) return;
    final remote = pictureInPictureRemote(_participants);
    final renderer = _renderers[remote?.id];
    final aspect = pictureInPictureAspect(
      renderer?.videoWidth ?? 0,
      renderer?.videoHeight ?? 0,
    );
    final next = (
      eligible: remote != null && !_finished,
      width: aspect.width,
      height: aspect.height,
    );
    if (next == _sentPictureInPicture) return;
    _sentPictureInPicture = next;
    unawaited(
      CallNotificationService.instance.setPictureInPicture(
        eligible: next.eligible,
        aspectWidth: next.width,
        aspectHeight: next.height,
      ),
    );
  }

  void _syncProximityScreenOff() {
    final next = proximityScreenOffWanted(
      kind: session.kind,
      speakerOn: _speakerOn,
      finished: _finished,
    );
    if (next == _sentProximityScreenOff) return;
    _sentProximityScreenOff = next;
    unawaited(CallNotificationService.instance.setProximityScreenOff(next));
  }

  void _syncRingback() {
    if (session.role != CallSessionRole.caller) return;
    final waiting =
        !session.everHadRemote && session.phase != CallSessionPhase.ended;
    unawaited(
      waiting
          ? NotificationSoundPlayer.instance.startRingback()
          : NotificationSoundPlayer.instance.stopRingback(),
    );
  }

  Future<void> _init() async {
    try {
      await session.ensurePermissions();
    } catch (_) {
      return;
    }

    unawaited(_startForegroundService());
    _armShowOverLockscreen();
    if (session.kind == CallKind.video) await WakelockPlus.enable();

    _speakerOn = session.kind == CallKind.video;
    unawaited(_applySpeakerRoute());
    _syncProximityScreenOff();

    if (session.phase == CallSessionPhase.active) await _attachEngine();
  }

  Future<void> _startForegroundService() {
    return CallNotificationService.instance
        .startOngoingCall(
          title: roomTitle(session.room),
          withCamera: session.kind == CallKind.video,
        )
        .catchError((e, s) => debugPrint('startOngoingCall failed: $e\n$s'));
  }

  void _armShowOverLockscreen() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(CallNotificationService.instance.setShowOverLockscreen(true));
    });
  }

  void _onPhase(CallSessionPhase phase) {
    if (!mounted) return;
    setState(() {});
    _syncRingback();
    if (phase == CallSessionPhase.active) unawaited(_attachEngine());
    if (phase == CallSessionPhase.ended) unawaited(_finish());
  }

  Future<void> _attachEngine() async {
    unawaited(_applySpeakerRoute());
    _participantsSub ??= session.engine.participantsStream.listen((p) {
      unawaited(_reconcileRenderers(p));
    });
    _statusSub ??= session.engine.statusStream.listen((status) {
      if (mounted) setState(() => _engineStatus = status);
    });
    _localStateSub ??= session.engine.localStateChangedStream.listen((_) {
      if (mounted) setState(() {});
    });
    _engineStatus = session.engine.status;
    await _reconcileRenderers(session.engine.participants);
  }

  Future<void> _reconcileRenderers(
    List<CallEngineParticipant> participants,
  ) async {
    for (final participant in participants) {
      var renderer = _renderers[participant.id];
      if (renderer == null) {
        renderer = RTCVideoRenderer();
        await renderer.initialize();
        renderer.onResize = _syncPictureInPicture;
        _renderers[participant.id] = renderer;
      }
      renderer.srcObject = participant.videoEnabled
          ? participant.videoStream
          : null;
    }
    final liveIds = participants.map((p) => p.id).toSet();
    final stale = _renderers.keys.where((id) => !liveIds.contains(id)).toList();
    for (final id in stale) {
      await _renderers.remove(id)?.dispose();
    }
    if (mounted) {
      setState(() {
        _participants = participants;
        if (participants.any((p) => !p.isLocal)) {
          _talkingSince ??= DateTime.now();
        }
      });
    }
    _syncPictureInPicture();
  }

  Future<void> _finish() async {
    if (_finished) return;
    _finished = true;
    _syncPictureInPicture();
    _syncProximityScreenOff();
    await CallNotificationService.instance.stopOngoingCall();
    await CallNotificationService.instance.setShowOverLockscreen(false);
    await WakelockPlus.disable();
    ref.read(activeCallProvider.notifier).set(null);
    if (!mounted) return;
    final message = session.failedMessage;
    if (session.endReason == CallEndReason.failed && message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    unawaited(NotificationSoundPlayer.instance.stopRingback());
    _phaseSub?.cancel();
    _remoteJoinedSub?.cancel();
    _participantsSub?.cancel();
    _statusSub?.cancel();
    _localStateSub?.cancel();
    for (final renderer in _renderers.values) {
      renderer.dispose();
    }
    super.dispose();
  }

  CallEngineParticipant? get _localParticipant =>
      _participants.where((p) => p.isLocal).firstOrNull;

  User? _userFor(VoipParticipantId id) {
    if (id.userId == 'local') return null;
    return session.room.unsafeGetUserFromMemoryOrFallback(id.userId);
  }

  bool _encrypting(CallEngineParticipant participant) {
    if (participant.isLocal) return !participant.encrypted;
    final bothEncrypted =
        (_localParticipant?.encrypted ?? false) && participant.encrypted;
    return !bothEncrypted;
  }

  Future<void> _toggleSpeaker() async {
    setState(() => _speakerOn = !_speakerOn);
    _syncProximityScreenOff();
    await _applySpeakerRoute();
  }

  Future<void> _applySpeakerRoute() async {
    await Helper.setSpeakerphoneOn(_speakerOn);
    await NotificationSoundPlayer.instance.restartRingbackForRouteChange();
  }

  Future<void> _toggleMute() async {
    final muted = _localParticipant?.audioMuted ?? false;
    await session.engine.setMicrophoneMuted(!muted);
    unawaited(session.refreshMembership());
  }

  Future<void> _toggleCamera() async {
    if (session.kind == CallKind.voice) {
      await session.engine.switchToVideo();
      unawaited(WakelockPlus.enable());
      session.kind = CallKind.video;
      _syncProximityScreenOff();
      setState(() {});
      unawaited(session.refreshMembership());
      return;
    }
    final cameraOn = _localParticipant?.videoEnabled ?? false;
    await session.engine.setCameraEnabled(!cameraOn);
    unawaited(session.refreshMembership());
  }

  CallViewParticipant _viewOf(CallEngineParticipant participant) =>
      CallViewParticipant(
        participant: participant,
        renderer: _renderers[participant.id],
        user: _userFor(participant.id),
        encrypting: _encrypting(participant),
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Theme(
          data: zunoDarkTheme,
          child: ValueListenableBuilder<bool>(
            valueListenable:
                CallNotificationService.instance.inPictureInPicture,
            builder: (context, inPictureInPicture, _) => inPictureInPicture
                ? Scaffold(
                    backgroundColor: Colors.black,
                    body: _buildPictureInPicture(),
                  )
                : _buildCall(),
          ),
        ),
      ),
    );
  }

  Widget _buildPictureInPicture() {
    final remote =
        pictureInPictureRemote(_participants) ??
        _participants.where((p) => !p.isLocal).firstOrNull;
    if (remote == null) return const SizedBox.shrink();
    return ParticipantTile(
      participant: remote,
      renderer: _renderers[remote.id],
      user: _userFor(remote.id),
      encrypting: _encrypting(remote),
      borderRadius: 0,
    );
  }

  Widget _buildCall() {
    final local = _localParticipant;
    final connecting = session.phase != CallSessionPhase.active;
    return CallView(
      room: session.room,
      kind: session.kind,
      connecting: connecting,
      calling: session.role == CallSessionRole.caller && !session.everHadRemote,
      local: local == null ? null : _viewOf(local),
      remote: [
        for (final participant in _participants)
          if (!participant.isLocal) _viewOf(participant),
      ],
      talkingSince: _talkingSince,
      reconnecting: _engineStatus == CallEngineStatus.reconnecting,
      quality: connecting ? CallQuality.good : session.engine.quality,
      speakerOn: _speakerOn,
      onToggleMute: _toggleMute,
      onToggleCamera: _toggleCamera,
      onSwitchCamera: () => session.engine.switchCamera(),
      onToggleSpeaker: _toggleSpeaker,
      onHangUp: () => session.hangUp(),
    );
  }
}
