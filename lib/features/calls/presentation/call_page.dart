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
import '../../../core/calls/platform/call_audio_output.dart';
import '../../../core/calls/platform/ongoing_call_presenter.dart';
import '../../../core/calls/platform/ringback_tone_player.dart';
import '../../../core/errors/best_effort.dart';
import '../../../core/matrix/matrix_ids.dart';
import '../../../core/matrix/room_title.dart';
import '../../../core/platform/platform_capabilities.dart';
import '../../../core/security/security_providers.dart';
import '../../../core/ui/zuno_theme.dart';
import '../../verification/presentation/confirm_person.dart';
import '../../verification/presentation/why_confirm_sheet.dart';
import 'call_audio_route.dart';
import 'call_confirm_prompt.dart';
import 'call_picture_in_picture.dart';
import 'call_proximity.dart';
import 'call_view.dart';
import 'participant_tile.dart';

const _videoDrainDelay = Duration(milliseconds: 500);

Future<void> _releaseAfterDetach(RTCVideoRenderer renderer) async {
  await runBestEffort(renderer.setSrcObject, label: 'detach call video');
  await Future<void>.delayed(_videoDrainDelay);
  await runBestEffort(renderer.dispose, label: 'release call video');
}

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
  late final OngoingCallPresenter _ongoingCall;
  late final RingbackTonePlayer _ringback;
  late final CallAudioOutput _audioOutput;
  late final bool _systemRoutesAudio;
  late final bool _detachVideoBeforeRelease;
  CallEngineStatus? _engineStatus;
  final Map<VoipParticipantId, RTCVideoRenderer> _renderers = {};
  List<CallEngineParticipant> _participants = [];

  CallAudioRoute _audioRoute = CallAudioRoute.earpiece;
  Set<CallAudioRoute> _headsets = const {};
  Future<void> _headsetSync = Future.value();
  bool _finished = false;
  DateTime? _talkingSince;
  Timer? _confirmPromptTimer;
  bool _talkedLongEnough = false;
  ({bool eligible, int width, int height})? _sentPictureInPicture;
  bool? _sentProximityScreenOff;

  @override
  void initState() {
    super.initState();
    _ongoingCall = ref.read(ongoingCallPresenterProvider);
    _ringback = ref.read(ringbackTonePlayerProvider);
    final capabilities = ref.read(platformCapabilitiesProvider);
    _audioOutput = callAudioOutputFor(capabilities);
    _systemRoutesAudio = capabilities.callKit;
    _detachVideoBeforeRelease = capabilities.videoRendererNeedsDetach;
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
      audioRoute: _audioRoute,
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
    unawaited(waiting ? _ringback.start() : _ringback.stop());
  }

  Future<void> _init() async {
    try {
      await session.ensurePermissions();
    } catch (_) {
      return;
    }
    if (!mounted || _finished) return;

    unawaited(_startForegroundService());
    _armShowOverLockscreen();
    if (session.kind == CallKind.video) await WakelockPlus.enable();

    final snapshot = await _audioOutput.read();
    _headsets = snapshot.headsets;
    if (!mounted || _finished) return;
    setState(
      () => _audioRoute =
          snapshot.route ?? startingRoute(session.kind, _headsets),
    );
    _audioOutput.watch(_onAudioDevicesChanged);
    if (!_systemRoutesAudio) unawaited(_applyAudioRoute());
    _syncProximityScreenOff();

    if (session.phase == CallSessionPhase.active) await _attachEngine();
  }

  Future<void> _startForegroundService() {
    return _ongoingCall
        .start(
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
    if (!_systemRoutesAudio) unawaited(_applyAudioRoute());
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
      final renderer = _renderers.remove(id);
      if (renderer == null) continue;
      if (_detachVideoBeforeRelease) {
        unawaited(_releaseAfterDetach(renderer));
      } else {
        await renderer.dispose();
      }
    }
    if (mounted) {
      setState(() {
        _participants = participants;
        if (participants.any((p) => !p.isLocal)) {
          _talkingSince ??= DateTime.now();
        }
      });
      if (_talkingSince != null) {
        _confirmPromptTimer ??= Timer(callConfirmPromptDelay, () {
          if (mounted) setState(() => _talkedLongEnough = true);
        });
      }
    }
    _syncPictureInPicture();
  }

  Future<void> _finish() async {
    if (_finished) return;
    _finished = true;
    final activeCall = ref.read(activeCallProvider.notifier);
    final current = ref.read(activeCallProvider);
    if (current == null || identical(current, session)) {
      _syncPictureInPicture();
      _syncProximityScreenOff();
      await _ongoingCall.stop();
      await CallNotificationService.instance.setShowOverLockscreen(false);
      await WakelockPlus.disable();
    }
    activeCall.clear(session);
    if (!mounted) return;
    final message = session.failedMessage;
    if (session.endReason == CallEndReason.failed && message != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    if (route != null &&
        !route.isCurrent &&
        ref.read(activeCallProvider) != null) {
      navigator.removeRoute(route);
      return;
    }
    if (route != null && route.isActive) {
      navigator.popUntil((r) => r == route);
    }
    navigator.pop();
  }

  @override
  void dispose() {
    _confirmPromptTimer?.cancel();
    unawaited(_ringback.stop());
    _audioOutput.unwatch();
    _phaseSub?.cancel();
    _remoteJoinedSub?.cancel();
    _participantsSub?.cancel();
    _statusSub?.cancel();
    _localStateSub?.cancel();
    for (final renderer in _renderers.values) {
      if (_detachVideoBeforeRelease) {
        unawaited(_releaseAfterDetach(renderer));
      } else {
        renderer.dispose();
      }
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

  void _onAudioDevicesChanged() {
    _headsetSync = _headsetSync.then((_) => _syncHeadsets());
  }

  Future<void> _syncHeadsets() async {
    final snapshot = await _audioOutput.read();
    if (!mounted || _finished) return;
    final headsets = snapshot.headsets;
    final next = routeAfterHeadsetChange(
      route: _audioRoute,
      before: _headsets,
      after: headsets,
      kind: session.kind,
    );
    _headsets = headsets;
    if (next != null) {
      unawaited(_setAudioRoute(next));
      return;
    }
    final actual = snapshot.route;
    if (actual == null || actual == _audioRoute) return;
    setState(() => _audioRoute = actual);
    _syncProximityScreenOff();
  }

  Future<void> _toggleSpeaker() =>
      _setAudioRoute(toggledRoute(_audioRoute, _headsets));

  Future<void> _setAudioRoute(CallAudioRoute route) async {
    if (!mounted || _finished) return;
    setState(() => _audioRoute = route);
    _syncProximityScreenOff();
    await _applyAudioRoute();
  }

  Future<void> _applyAudioRoute() async {
    await _audioOutput.apply(_audioRoute);
    await _ringback.restartForRouteChange();
  }

  Future<void> _toggleMute() async {
    final muted = _localParticipant?.audioMuted ?? false;
    await session.engine.setMicrophoneMuted(!muted);
    unawaited(session.refreshMembership());
  }

  Future<void> _toggleCamera() async {
    if (session.kind == CallKind.voice) {
      await session.engine.switchToVideo();
      if (!mounted || _finished) return;
      unawaited(WakelockPlus.enable());
      session.kind = CallKind.video;
      if (_audioRoute == CallAudioRoute.earpiece) {
        unawaited(_setAudioRoute(CallAudioRoute.speaker));
      }
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
    final confirmUserId = _confirmPromptUserId();
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
                : _buildCall(context, confirmUserId),
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

  String? _confirmPromptUserId() {
    if (!session.room.isDirectChat) return null;
    final remotes = _participants.where((p) => !p.isLocal).toList();
    if (remotes.length != 1) return null;
    final userId = remotes.single.id.userId;
    final wanted = callConfirmPromptWanted(
      trust: ref.watch(userTrustProvider(userId)),
      deviceReady: ref.watch(
        accountSecurityFactsProvider.select((facts) {
          final value = facts.value;
          return value != null &&
              value.recoveryExists &&
              value.thisDeviceHasIdentityKeys;
        }),
      ),
      declined: ref.watch(callConfirmPromptStoreProvider).declined(userId),
      talkedLongEnough: _talkedLongEnough,
    );
    return wanted ? userId : null;
  }

  Future<void> _explainConfirming(BuildContext context, String userId) async {
    final confirm = await showWhyConfirmSheet(
      context,
      name: withoutServer(userId),
    );
    if (confirm == null || !context.mounted) return;
    if (!confirm) {
      await ref.read(callConfirmPromptStoreProvider).decline(userId);
      if (mounted) setState(() {});
      return;
    }
    await confirmPerson(context, ref, userId, picturesFirst: true);
  }

  Widget _buildCall(BuildContext context, String? confirmUserId) {
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
      audioRoute: _audioRoute,
      onToggleMute: _toggleMute,
      onToggleCamera: _toggleCamera,
      onSwitchCamera: () => session.engine.switchCamera(),
      onToggleSpeaker: _toggleSpeaker,
      onHangUp: () => session.hangUp(byUser: true),
      confirmName: confirmUserId == null ? null : withoutServer(confirmUserId),
      onConfirmPerson: confirmUserId == null
          ? null
          : () => _explainConfirming(context, confirmUserId),
    );
  }
}
