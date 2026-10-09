import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:matrix/matrix.dart' hide CallSession;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../errors/best_effort.dart';
import '../errors/global_error_handler.dart';
import '../matrix/room_title.dart';
import '../platform/platform_capabilities.dart';
import 'active_call_provider.dart';
import 'call_audio_route.dart';
import 'call_picture_in_picture.dart';
import 'call_proximity.dart';
import 'matrixrtc/call_session.dart';
import 'models/call_engine_participant.dart';
import 'models/call_engine_status.dart';
import 'models/call_kind.dart';
import 'models/call_quality.dart';
import 'models/call_status.dart';
import 'models/call_surface.dart';
import 'models/voip_participant_id.dart';
import 'notifications/call_notification_service.dart';
import 'platform/call_audio_output.dart';
import 'platform/ongoing_call_presenter.dart';
import 'platform/ringback_tone_player.dart';
import 'serial_lock.dart';

const _videoDrainDelay = Duration(milliseconds: 500);
const _callConfirmPromptDelay = Duration(seconds: 30);

typedef _PictureInPictureOffer = ({
  bool eligible,
  int width,
  int height,
  String? streamId,
  String? ownerTag,
});

Future<void> _releaseAfterDetach(RTCVideoRenderer renderer) async {
  await runBestEffort(renderer.setSrcObject, label: 'detach call video');
  await Future<void>.delayed(_videoDrainDelay);
  await runBestEffort(renderer.dispose, label: 'release call video');
}

final activeCallControllerProvider =
    NotifierProvider<ActiveCallControllers, ActiveCallController?>(
      ActiveCallControllers.new,
    );

class ActiveCallControllers extends Notifier<ActiveCallController?> {
  final _deviceEffects = SerialLock();
  ActiveCallController? _current;

  @override
  ActiveCallController? build() {
    ref.listen<CallSession?>(activeCallProvider, (_, session) {
      if (identical(_current?.session, session)) return;
      _current?.leave();
      state = _current = session == null ? null : _start(session);
    });
    ref.onDispose(() => _current?.close());
    final session = ref.read(activeCallProvider);
    return _current = session == null ? null : _start(session);
  }

  ActiveCallController _start(CallSession session) {
    return ActiveCallController(
      session: session,
      ongoingCall: ref.read(ongoingCallPresenterProvider),
      ringback: ref.read(ringbackTonePlayerProvider),
      capabilities: ref.read(platformCapabilitiesProvider),
      deviceEffects: _deviceEffects,
      ownsDevice: () {
        if (!ref.mounted) return false;
        final current = ref.read(activeCallProvider);
        return current == null || identical(current, session);
      },
      release: () {
        if (ref.mounted) ref.read(activeCallProvider.notifier).clear(session);
      },
    )..start();
  }
}

class ActiveCallController extends ChangeNotifier {
  ActiveCallController({
    required this.session,
    required this._ongoingCall,
    required this._ringback,
    required PlatformCapabilities capabilities,
    required this._deviceEffects,
    required this._ownsDevice,
    required this._release,
  }) : _audioOutput = callAudioOutputFor(capabilities),
       _systemRoutesAudio = capabilities.callKit,
       _detachVideoBeforeRelease = capabilities.videoRendererNeedsDetach;

  final CallSession session;
  final OngoingCallPresenter _ongoingCall;
  final RingbackTonePlayer _ringback;
  final CallAudioOutput _audioOutput;
  final bool _systemRoutesAudio;
  final bool _detachVideoBeforeRelease;
  final SerialLock _deviceEffects;
  final bool Function() _ownsDevice;
  final void Function() _release;

  StreamSubscription<CallSessionPhase>? _phaseSub;
  StreamSubscription<void>? _remoteJoinedSub;
  StreamSubscription<List<CallEngineParticipant>>? _participantsSub;
  StreamSubscription<CallEngineStatus>? _statusSub;
  StreamSubscription<void>? _localStateSub;
  final Map<VoipParticipantId, RTCVideoRenderer> _renderers = {};
  List<CallEngineParticipant> _roster = const [];
  List<CallEngineParticipant>? _pendingRoster;
  Future<void>? _reconciling;
  List<CallEngineParticipant> _participants = const [];
  CallEngineParticipant? _local;
  List<CallEngineParticipant> _remotes = const [];
  CallEngineStatus? _engineStatus;
  late CallAudioRoute _audioRoute = startingRoute(session.kind, const {});
  Set<CallAudioRoute> _headsets = const {};
  Future<void> _headsetSync = Future.value();
  bool _routeChosen = false;
  bool _microphoneOpen = false;
  bool _audioRouted = false;
  DateTime? _talkingSince;
  Timer? _talkedLongEnoughTimer;
  bool _talkedLongEnough = false;
  bool _started = false;
  bool _finished = false;
  bool _screenOpen = false;
  bool _released = false;
  _PictureInPictureOffer? _sentPictureInPicture;
  bool? _sentProximityScreenOff;
  bool? _sentShowOverLockscreen;

  List<CallEngineParticipant> get participants => _participants;

  CallEngineParticipant? get local => _local;

  List<CallEngineParticipant> get remotes => _remotes;

  RTCVideoRenderer? rendererFor(VoipParticipantId id) => _renderers[id];

  CallAudioRoute get audioRoute => _audioRoute;

  DateTime? get talkingSince => _talkingSince;

  bool get talkedLongEnough => _talkedLongEnough;

  CallStatus get status {
    final local = _local;
    return callStatus(
      calling: calling,
      connecting: connecting,
      someoneHere: !connecting && _remotes.isNotEmpty,
      keysPending:
          local == null || encrypting(local) || _remotes.any(encrypting),
    );
  }

  bool get finished => _finished;

  bool get connecting => session.phase != CallSessionPhase.active;

  bool get calling =>
      session.role == CallSessionRole.caller && !session.everHadRemote;

  bool get reconnecting => _engineStatus == CallEngineStatus.reconnecting;

  CallQuality get quality =>
      connecting ? CallQuality.good : session.engine.quality;

  CallEngineParticipant? get videoRemote =>
      _finished ? null : pictureInPictureRemote(_participants);

  CallSurface get surface {
    if (_finished) return CallSurface.none;
    if (_pictureInPicture.value) return CallSurface.pictureInPicture;
    if (_screenOpen) return CallSurface.screen;
    return videoRemote == null ? CallSurface.bar : CallSurface.window;
  }

  bool get replaced => !_ownsDevice();

  bool get screenOpen => _screenOpen;

  set screenOpen(bool open) {
    if (_screenOpen == open || _released) return;
    _screenOpen = open;
    _resyncVideo();
    _syncProximityScreenOff();
    _syncShowOverLockscreen();
    _notify();
    _releaseIfDone();
  }

  User? userFor(CallEngineParticipant participant) {
    final room = session.room;
    final userId = participant.isLocal
        ? room.client.userID
        : participant.id.userId;
    if (userId == null) return null;
    return room.unsafeGetUserFromMemoryOrFallback(userId);
  }

  bool encrypting(CallEngineParticipant participant) {
    if (participant.isLocal) return !participant.encrypted;
    return !((_local?.encrypted ?? false) && participant.encrypted);
  }

  void start() {
    _pictureInPicture.addListener(_onPictureInPicture);
    _phaseSub = session.phaseStream.listen(_onPhase);
    _remoteJoinedSub = session.remoteJoinedStream.listen(
      (_) => _syncRingback(),
    );
    unawaited(session.engine.microphoneCaptured.then(_onMicrophoneCaptured));
    unawaited(_attachEngine());
    _syncRingback();
    if (session.phase == CallSessionPhase.ended) {
      scheduleMicrotask(leave);
      return;
    }
    unawaited(_init());
  }

  void leave() => unawaited(_finish());

  void close() {
    if (_released) return;
    _released = true;
    _talkedLongEnoughTimer?.cancel();
    _pictureInPicture.removeListener(_onPictureInPicture);
    _cancelSubscriptions();
    _audioOutput.unwatch();
  }

  Future<void> toggleMute() async {
    final muted = _local?.audioMuted ?? false;
    await session.engine.setMicrophoneMuted(!muted);
    unawaited(session.refreshMembership());
  }

  Future<bool> toggleCamera() async {
    final turningOn =
        session.kind == CallKind.voice || !(_local?.videoEnabled ?? false);
    try {
      await _toggleCameraOrThrow();
      return true;
    } catch (e) {
      logCaught('toggle camera', e);
      return !turningOn;
    }
  }

  Future<void> switchCamera() => session.engine.switchCamera();

  Future<void> toggleSpeaker() =>
      _setAudioRoute(toggledRoute(_audioRoute, _headsets));

  Future<void> hangUp() => session.hangUp(byUser: true);

  void _notify() {
    if (!_released) notifyListeners();
  }

  Future<void> _init() async {
    try {
      await session.ensurePermissions();
    } catch (_) {
      return;
    }
    if (_finished) return;
    await _deviceEffects.run(() async {
      if (_finished) return;
      unawaited(_startOngoingCall());
      if (session.kind == CallKind.video) await _keepScreenOn();
    });
    if (_finished) return;
    _started = true;
    _syncShowOverLockscreen();
    final snapshot = await _audioOutput.read();
    _headsets = snapshot.headsets;
    if (_finished) return;
    if (!_routeChosen) {
      _audioRoute = snapshot.route ?? startingRoute(session.kind, _headsets);
      _routeChosen = true;
    }
    _notify();
    _audioOutput.watch(_onAudioDevicesChanged);
    unawaited(_routeAudio());
    _syncProximityScreenOff();
  }

  Future<void> _startOngoingCall() => _ongoingCall
      .start(
        title: roomTitle(session.room),
        withCamera: session.kind == CallKind.video,
      )
      .catchError((e, s) => debugPrint('startOngoingCall failed: $e\n$s'));

  void _onPhase(CallSessionPhase phase) {
    if (_finished) return;
    _notify();
    _syncRingback();
    if (phase == CallSessionPhase.ended) leave();
  }

  Future<void> _attachEngine() async {
    if (_finished || _released) return;
    _participantsSub ??= session.engine.participantsStream.listen((p) {
      unawaited(_reconcile(p));
    });
    _statusSub ??= session.engine.statusStream.listen((status) {
      _engineStatus = status;
      _notify();
    });
    _localStateSub ??= session.engine.localStateChangedStream.listen(
      (_) => _notify(),
    );
    _engineStatus = session.engine.status;
    await _reconcile(session.engine.participants);
  }

  ValueListenable<bool> get _pictureInPicture =>
      CallNotificationService.instance.inPictureInPicture;

  void _onPictureInPicture() {
    _resyncVideo();
    _notify();
  }

  void _resyncVideo() {
    if (_finished) return;
    unawaited(_reconcile(_roster));
  }

  Set<VoipParticipantId> _shownVideo(List<CallEngineParticipant> participants) {
    if (surface == CallSurface.screen) {
      return {
        for (final participant in participants)
          if (participant.videoEnabled) participant.id,
      };
    }
    final remote = pictureInPictureRemote(participants);
    return {?remote?.id};
  }

  Future<RTCVideoRenderer?> _createRenderer() async {
    final renderer = RTCVideoRenderer();
    try {
      await renderer.initialize();
      return renderer;
    } catch (e) {
      logCaught('create call video', e);
      unawaited(runBestEffort(renderer.dispose, label: 'release call video'));
      return null;
    }
  }

  Future<void> _reconcile(List<CallEngineParticipant> participants) {
    _roster = participants;
    _pendingRoster = participants;
    return _reconciling ??= _drainRoster();
  }

  Future<void> _drainRoster() async {
    try {
      while (!_finished) {
        final next = _pendingRoster;
        if (next == null) return;
        _pendingRoster = null;
        await _reconcileRenderers(next);
      }
    } finally {
      _reconciling = null;
    }
  }

  Future<void> _reconcileRenderers(
    List<CallEngineParticipant> participants,
  ) async {
    if (_finished) return;
    final shown = _shownVideo(participants);
    for (final participant in participants) {
      final stream = participant.videoEnabled ? participant.videoStream : null;
      var renderer = _renderers[participant.id];
      if (renderer == null) {
        if (stream == null) continue;
        renderer = await _createRenderer();
        if (_finished) {
          if (renderer != null) await _releaseRenderer(renderer);
          return;
        }
        if (renderer == null) continue;
        renderer.onResize = _syncPictureInPicture;
        _renderers[participant.id] = renderer;
      }
      final wanted = shown.contains(participant.id) ? stream : null;
      if (!_sameVideo(renderer.srcObject, wanted)) renderer.srcObject = wanted;
    }
    final liveIds = participants.map((p) => p.id).toSet();
    final stale = _renderers.keys.where((id) => !liveIds.contains(id)).toList();
    for (final id in stale) {
      final renderer = _renderers.remove(id);
      if (renderer != null) await _releaseRenderer(renderer);
    }
    if (_finished) return;
    _participants = participants;
    _local = participants.where((p) => p.isLocal).firstOrNull;
    _remotes = [
      for (final participant in participants)
        if (!participant.isLocal) participant,
    ];
    if (_remotes.isNotEmpty && _talkingSince == null) {
      _talkingSince = DateTime.now();
      _talkedLongEnoughTimer = Timer(_callConfirmPromptDelay, () {
        _talkedLongEnough = true;
        _notify();
      });
    }
    _notify();
    _syncPictureInPicture();
  }

  bool _sameVideo(MediaStream? attached, MediaStream? wanted) =>
      attached?.id == wanted?.id && attached?.ownerTag == wanted?.ownerTag;

  Future<void> _releaseRenderer(RTCVideoRenderer renderer) async {
    if (_detachVideoBeforeRelease) {
      unawaited(_releaseAfterDetach(renderer));
    } else {
      await runBestEffort(renderer.dispose, label: 'release call video');
    }
  }

  void _syncPictureInPicture() {
    if (_finished) return;
    final remote = pictureInPictureRemote(_participants);
    final renderer = _renderers[remote?.id];
    final aspect = pictureInPictureAspect(
      renderer?.videoWidth ?? 0,
      renderer?.videoHeight ?? 0,
    );
    final video = remote?.videoStream;
    _sendPictureInPicture((
      eligible: remote != null,
      width: aspect.width,
      height: aspect.height,
      streamId: video?.id,
      ownerTag: video?.ownerTag,
    ));
  }

  void _sendPictureInPicture(_PictureInPictureOffer next) {
    if (next == _sentPictureInPicture) return;
    _sentPictureInPicture = next;
    unawaited(
      runBestEffort(
        () => CallNotificationService.instance.setPictureInPicture(
          eligible: next.eligible,
          aspectWidth: next.width,
          aspectHeight: next.height,
          streamId: next.streamId,
          ownerTag: next.ownerTag,
        ),
        label: 'offer picture-in-picture',
      ),
    );
  }

  void _syncProximityScreenOff() {
    if (!_started || _finished) return;
    _sendProximityScreenOff(
      proximityScreenOffWanted(
        kind: session.kind,
        audioRoute: _audioRoute,
        screenOpen: _screenOpen,
      ),
    );
  }

  void _sendProximityScreenOff(bool enabled) {
    if (enabled == _sentProximityScreenOff) return;
    _sentProximityScreenOff = enabled;
    unawaited(
      runBestEffort(
        () => CallNotificationService.instance.setProximityScreenOff(enabled),
        label: 'blank the screen at the ear',
      ),
    );
  }

  void _syncShowOverLockscreen() {
    if (!_started || _finished) return;
    if (!_screenOpen) {
      _sendShowOverLockscreen(false);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_started && !_finished && _screenOpen) _sendShowOverLockscreen(true);
    });
  }

  void _sendShowOverLockscreen(bool show) {
    if (show == _sentShowOverLockscreen) return;
    _sentShowOverLockscreen = show;
    unawaited(_deviceEffects.run(() => _setShowOverLockscreen(show)));
  }

  void _syncRingback() {
    if (session.role != CallSessionRole.caller) return;
    final waiting =
        !session.everHadRemote && session.phase != CallSessionPhase.ended;
    final routed = _systemRoutesAudio || _audioRouted;
    unawaited(waiting && routed ? _ringback.start() : _ringback.stop());
  }

  void _onMicrophoneCaptured(void _) {
    _microphoneOpen = true;
    unawaited(_routeAudio());
  }

  Future<void> _routeAudio() async {
    if (!_routeChosen || !_microphoneOpen || _audioRouted) return;
    if (_finished || _released) return;
    _audioRouted = true;
    if (!_systemRoutesAudio) await _applyAudioRoute();
    if (_finished || _released) return;
    _syncRingback();
  }

  void _onAudioDevicesChanged() {
    _headsetSync = _headsetSync.then((_) => _syncHeadsets());
  }

  Future<void> _syncHeadsets() async {
    final snapshot = await _audioOutput.read();
    if (_finished) return;
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
    _audioRoute = actual;
    _notify();
    _syncProximityScreenOff();
  }

  Future<void> _setAudioRoute(CallAudioRoute route) async {
    if (_finished) return;
    _audioRoute = route;
    _routeChosen = true;
    _notify();
    _syncProximityScreenOff();
    await _applyAudioRoute();
  }

  Future<void> _applyAudioRoute() async {
    await runBestEffort(
      () => _audioOutput.apply(_audioRoute),
      label: 'route call audio',
    );
    await _ringback.restartForRouteChange();
  }

  Future<void> _keepScreenOn() =>
      runBestEffort(WakelockPlus.enable, label: 'keep the screen on');

  Future<void> _setShowOverLockscreen(bool show) => runBestEffort(
    () => CallNotificationService.instance.setShowOverLockscreen(show),
    label: 'show over the lock screen',
  );

  Future<void> _toggleCameraOrThrow() async {
    if (session.kind == CallKind.voice) {
      await session.engine.switchToVideo();
      if (_finished) return;
      unawaited(_keepScreenOn());
      session.kind = CallKind.video;
      if (_audioRoute == CallAudioRoute.earpiece) {
        unawaited(_setAudioRoute(CallAudioRoute.speaker));
      }
      _syncProximityScreenOff();
      _notify();
      unawaited(session.refreshMembership());
      return;
    }
    final cameraOn = _local?.videoEnabled ?? false;
    await session.engine.setCameraEnabled(!cameraOn);
    unawaited(session.refreshMembership());
  }

  Future<void> _finish() async {
    if (_finished) return;
    _finished = true;
    _talkedLongEnoughTimer?.cancel();
    _release();
    _notify();
    unawaited(_ringback.stop());
    _audioOutput.unwatch();
    await _deviceEffects.run(_releaseDevice);
    _releaseMedia();
    final message = session.failedMessage;
    if (session.endReason == CallEndReason.failed && message != null) {
      globalScaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
    _releaseIfDone();
  }

  Future<void> _releaseDevice() async {
    if (!_ownsDevice()) return;
    final offered = _sentPictureInPicture;
    final aspect = offered == null
        ? pictureInPictureAspect(0, 0)
        : (width: offered.width, height: offered.height);
    _sendPictureInPicture((
      eligible: false,
      width: aspect.width,
      height: aspect.height,
      streamId: null,
      ownerTag: null,
    ));
    _sendProximityScreenOff(false);
    await runBestEffort(
      _ongoingCall.stop,
      label: 'stop the ongoing-call notice',
    );
    _sentShowOverLockscreen = false;
    await _setShowOverLockscreen(false);
    await runBestEffort(WakelockPlus.disable, label: 'let the screen sleep');
  }

  void _releaseMedia() {
    _pictureInPicture.removeListener(_onPictureInPicture);
    _cancelSubscriptions();
    _pendingRoster = null;
    for (final renderer in _renderers.values) {
      unawaited(_releaseRenderer(renderer));
    }
    _renderers.clear();
  }

  void _releaseIfDone() {
    if (!_finished || _screenOpen || _released) return;
    _released = true;
    dispose();
  }

  void _cancelSubscriptions() {
    unawaited(_phaseSub?.cancel());
    unawaited(_remoteJoinedSub?.cancel());
    unawaited(_participantsSub?.cancel());
    unawaited(_statusSub?.cancel());
    unawaited(_localStateSub?.cancel());
  }
}
