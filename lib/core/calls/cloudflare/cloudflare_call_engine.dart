import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show debugPrint, listEquals, visibleForTesting;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

import '../../errors/backoff.dart';
import '../../errors/best_effort.dart';
import '../call_engine.dart';
import '../models/call_engine_participant.dart';
import '../models/call_engine_status.dart';
import '../models/call_kind.dart';
import '../models/call_quality.dart';
import '../models/voip_participant_id.dart';
import 'call_quality_policy.dart';
import 'calls_gateway_credentials.dart';
import 'cloudflare_api_client.dart';
import 'negotiation_lock.dart';
import 'remote_track_plan.dart';
import 'video_codec_preference.dart';

CfSessionDescription _cfDescription(RTCSessionDescription description) =>
    CfSessionDescription(sdp: description.sdp!, type: description.type!);

Future<void> _quietly(Future<void> Function()? action) async {
  if (action == null) return;
  try {
    await action();
  } catch (_) {}
}

class CloudflareCallEngine implements CallEngine {
  final CloudflareApiClient _api;
  CallKind _kind;

  RTCPeerConnection? _pc;
  String? _sessionId;

  MediaStream? _localAudioStream;
  MediaStream? _localVideoStream;
  RTCRtpTransceiver? _localAudioTransceiver;
  RTCRtpTransceiver? _localVideoTransceiver;
  bool _micMuted = false;
  bool _cameraEnabled;

  CallEngineStatus _status = CallEngineStatus.connecting;
  final _statusController = StreamController<CallEngineStatus>.broadcast();

  final Map<VoipParticipantId, _RemoteParticipant> _remote = {};
  final Map<String, ({VoipParticipantId participant, String trackName})>
  _midOwners = {};
  final _participantsController =
      StreamController<List<CallEngineParticipant>>.broadcast();

  KeyProvider? _keyProvider;
  final Map<String, FrameCryptor> _frameCryptors = {};
  final Set<String> _senderWrapsInFlight = {};

  final List<Map<String, Object?>> iceServers;
  final bool lowDataMode;

  Timer? _statsTimer;
  StatsCounters? _lastCounters;
  final _classifier = CallQualityClassifier();
  final _localStateController = StreamController<void>.broadcast();

  final _negotiationLock = NegotiationLock();

  bool _isLiveConnection(RTCPeerConnection pc) => !_left && identical(_pc, pc);

  CloudflareCallEngine({
    required Uri gatewayBaseUri,
    required GatewayAuthorizationProvider gatewayAuthorizationProvider,
    required CallKind kind,
    this.iceServers = const [],
    this.lowDataMode = false,
    http.Client? httpClient,
  }) : _api = CloudflareApiClient(
         baseUri: gatewayBaseUri,
         authorizationProvider: gatewayAuthorizationProvider,
         httpClient: httpClient,
       ),
       _kind = kind,
       _cameraEnabled = kind == CallKind.video;

  Map<String, Object?> get _videoConstraints => {
    'facingMode': 'user',
    'width': lowDataMode ? 640 : 854,
    'height': lowDataMode ? 360 : 480,
    'frameRate': lowDataMode ? 24 : 30,
  };

  @override
  Future<void> setEncryptionKey(Uint8List key) async {
    final existingKeyProvider = _keyProvider;
    final hadAudioCryptor = _frameCryptors.containsKey('local-audio');
    final hadVideoCryptor = _frameCryptors.containsKey('local-video');
    final keyProvider =
        existingKeyProvider ??
        await frameCryptorFactory.createDefaultKeyProvider(
          KeyProviderOptions(
            sharedKey: true,
            ratchetSalt: Uint8List.fromList('zuno.calls.e2ee'.codeUnits),
            ratchetWindowSize: 16,
          ),
        );
    try {
      await keyProvider.setSharedKey(key: key);
      await _wrapLocalSenders(keyProvider);
    } catch (_) {
      if (!hadAudioCryptor) {
        await _frameCryptors.remove('local-audio')?.dispose();
      }
      if (!hadVideoCryptor) {
        await _frameCryptors.remove('local-video')?.dispose();
      }
      if (existingKeyProvider == null) {
        await keyProvider.dispose();
      }
      rethrow;
    }
    _keyProvider = keyProvider;
    await runBestEffort(
      () => _wrapLocalSenders(keyProvider),
      label: 'wrap senders after key',
    );
    for (final remote in _remote.values.toList()) {
      for (final entry in remote.recvTransceivers.entries.toList()) {
        final label = '${remote.id}-${entry.key}';
        await runBestEffort(
          () => _wrapReceiver(label, entry.value.receiver),
          label: 'wrap receiver $label after key',
        );
      }
    }
    _applyLocalTrackState();
    _notifyParticipants();
    _notifyLocalStateChanged();
    for (final remote in _remote.values.toList()) {
      unawaited(
        runBestEffort(
          () => _syncRemoteTracks(remote),
          label: 'pull after key for ${remote.id}',
        ),
      );
    }
  }

  void _applyLocalTrackState() {
    final audioEncrypted = _frameCryptors.containsKey('local-audio');
    final videoEncrypted = _frameCryptors.containsKey('local-video');
    for (final track
        in _localAudioStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = audioEncrypted && !_micMuted;
    }
    for (final track
        in _localVideoStream?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = videoEncrypted && _cameraEnabled;
    }
  }

  Future<void> _wrapLocalSenders(KeyProvider keyProvider) async {
    if (_localAudioTransceiver case final t?) {
      await _wrapSender('local-audio', t.sender, keyProvider);
    }
    if (_localVideoTransceiver case final t?) {
      await _wrapSender('local-video', t.sender, keyProvider);
    }
  }

  Future<void> _wrapSender(
    String label,
    RTCRtpSender sender,
    KeyProvider keyProvider,
  ) async {
    if (_frameCryptors.containsKey(label) ||
        sender.track == null ||
        !_senderWrapsInFlight.add(label)) {
      return;
    }
    try {
      final cryptor = await frameCryptorFactory.createFrameCryptorForRtpSender(
        participantId: label,
        sender: sender,
        algorithm: Algorithm.kAesGcm,
        keyProvider: keyProvider,
      );
      try {
        await cryptor.setEnabled(true);
      } catch (_) {
        await runBestEffort(
          cryptor.dispose,
          label: 'dispose failed sender cryptor $label',
        );
        rethrow;
      }
      _frameCryptors[label] = cryptor;
    } finally {
      _senderWrapsInFlight.remove(label);
    }
  }

  Future<void> _preferVideoCodecs(RTCRtpTransceiver transceiver) =>
      runBestEffort(() async {
        final capabilities = await getRtpSenderCapabilities('video');
        await transceiver.setCodecPreferences(
          orderVideoCodecs(capabilities.codecs ?? const []),
        );
      }, label: 'set video codec preferences');

  Future<void> _wrapReceiver(String label, RTCRtpReceiver receiver) async {
    final keyProvider = _keyProvider;
    if (keyProvider == null || _frameCryptors.containsKey(label)) return;
    final cryptor = await frameCryptorFactory.createFrameCryptorForRtpReceiver(
      participantId: label,
      receiver: receiver,
      algorithm: Algorithm.kAesGcm,
      keyProvider: keyProvider,
    );
    try {
      await cryptor.setEnabled(true);
    } catch (_) {
      await runBestEffort(
        cryptor.dispose,
        label: 'dispose failed receiver cryptor $label',
      );
      rethrow;
    }
    _frameCryptors[label] = cryptor;
  }

  @override
  CallEngineStatus get status => _status;
  @override
  Stream<CallEngineStatus> get statusStream => _statusController.stream;

  static const _localId = VoipParticipantId(userId: 'local', deviceId: 'local');

  @override
  List<CallEngineParticipant> get participants => [
    CallEngineParticipant(
      id: _localId,
      isLocal: true,
      audioStream: _localAudioStream,
      videoStream: _localVideoStream,
      audioMuted: _micMuted,
      videoEnabled: _cameraEnabled,
      encrypted: _keyProvider != null,
      lowBandwidth: _classifier.current != CallQuality.good,
      frontCamera: _frontCamera,
    ),
    ..._remote.values.map((r) => r.toParticipant()),
  ];
  @override
  Stream<List<CallEngineParticipant>> get participantsStream =>
      _participantsController.stream;

  @override
  CallKind get kind => _kind;

  @override
  CallQuality get quality => _classifier.current;
  @override
  Stream<void> get localStateChangedStream => _localStateController.stream;

  void _notifyLocalStateChanged() {
    if (_localStateController.isClosed) return;
    _localStateController.add(null);
  }

  CallQuality get _combinedQuality => combineQuality(
    local: _classifier.current,
    anyRemoteLowBandwidth: _remote.values.any((r) => r.lowBandwidth),
  );

  void _setStatus(CallEngineStatus status) {
    _status = status;
    if (_statusController.isClosed) return;
    _statusController.add(status);
  }

  List<CallEngineParticipant>? _lastEmittedParticipants;

  void _notifyParticipants() {
    if (_participantsController.isClosed) return;
    final snapshot = participants;
    if (listEquals(_lastEmittedParticipants, snapshot)) return;
    _lastEmittedParticipants = snapshot;
    _participantsController.add(snapshot);
  }

  Future<String> _currentMid(
    RTCPeerConnection pc,
    RTCRtpTransceiver transceiver,
  ) async {
    final senderId = transceiver.sender.senderId;
    for (final t in await pc.getTransceivers()) {
      if (t.sender.senderId == senderId) return t.mid;
    }
    return transceiver.mid;
  }

  Future<void> _closeTracks(List<String> mids, {bool force = false}) async {
    final pc = _pc;
    final sessionId = _sessionId;
    if (pc == null || sessionId == null || mids.isEmpty) return;
    final current = await pc.getLocalDescription();
    if (current == null || current.sdp == null || current.type == null) return;

    try {
      await _closeTracksOrThrow(pc, sessionId, mids, force, current);
    } catch (e, s) {
      debugPrint('[Call] closing tracks $mids failed (ignored): $e\n$s');
    }
  }

  Future<void> _closeTracksOrThrow(
    RTCPeerConnection pc,
    String sessionId,
    List<String> mids,
    bool force,
    RTCSessionDescription current,
  ) async {
    final result = await _api.closeTracks(
      sessionId: sessionId,
      mids: mids,
      force: force,
      sessionDescription: _cfDescription(current),
    );
    if (!_isLiveConnection(pc)) return;
    final offered = result.sessionDescription;
    if (!result.requiresImmediateRenegotiation || offered == null) return;
    await pc.setRemoteDescription(
      RTCSessionDescription(offered.sdp, offered.type),
    );
    if (!_isLiveConnection(pc)) return;
    final localDescription = await _liveLocalAnswer(pc);
    if (localDescription == null) return;
    await _api.renegotiate(
      sessionId: sessionId,
      offer: _cfDescription(localDescription),
    );
  }

  static const _iceIdleCutoff = Duration(milliseconds: 500);
  static const _iceHardCeiling = Duration(seconds: 3);

  Future<RTCSessionDescription> _completeLocalOffer(
    RTCPeerConnection pc,
  ) async {
    final completer = Completer<void>();
    void complete() {
      if (!completer.isCompleted) completer.complete();
    }

    Timer? idleTimer;
    void resetIdleTimer() {
      idleTimer?.cancel();
      idleTimer = Timer(_iceIdleCutoff, complete);
    }

    pc.onIceGatheringState = (state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) {
        complete();
      }
    };
    pc.onIceCandidate = (_) => resetIdleTimer();
    resetIdleTimer();

    if (await pc.getIceGatheringState() ==
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      complete();
    }
    await completer.future.timeout(_iceHardCeiling, onTimeout: () {});
    pc.onIceGatheringState = null;
    pc.onIceCandidate = null;
    idleTimer?.cancel();
    return (await pc.getLocalDescription())!;
  }

  Future<RTCSessionDescription?> _liveLocalOffer(RTCPeerConnection pc) async {
    final offer = await pc.createOffer();
    if (!_isLiveConnection(pc)) return null;
    return _liveLocalDescription(pc, offer);
  }

  Future<RTCSessionDescription?> _liveLocalAnswer(RTCPeerConnection pc) async {
    final answer = await pc.createAnswer();
    if (!_isLiveConnection(pc)) return null;
    return _liveLocalDescription(pc, answer);
  }

  Future<RTCSessionDescription?> _liveLocalDescription(
    RTCPeerConnection pc,
    RTCSessionDescription description,
  ) async {
    await pc.setLocalDescription(description);
    if (!_isLiveConnection(pc)) return null;
    final localDescription = await _completeLocalOffer(pc);
    return _isLiveConnection(pc) ? localDescription : null;
  }

  @override
  Future<void> join() async {
    final mediaFuture = navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': _kind == CallKind.video ? _videoConstraints : false,
    });
    var mediaAdopted = false;
    MediaStream? capturedStream;
    try {
      final results = await Future.wait<Object?>(
        [_openConnection().then((_) => null), mediaFuture],
        eagerError: true,
        cleanUp: (value) {
          if (value is MediaStream) unawaited(_quietly(value.dispose));
        },
      );
      final stream = results[1] as MediaStream;
      capturedStream = stream;
      if (_left) {
        await _discardLocalCapture(stream);
        return;
      }

      _localAudioStream = await createLocalMediaStream('local_audio');
      for (final track in stream.getAudioTracks()) {
        await _localAudioStream!.addTrack(track);
      }
      if (_kind == CallKind.video) {
        _localVideoStream = await createLocalMediaStream('local_video');
        for (final track in stream.getVideoTracks()) {
          await _localVideoStream!.addTrack(track);
        }
        _frontCamera = true;
      }
      mediaAdopted = true;
      if (_left) {
        await _discardLocalCapture(stream);
        return;
      }

      await _attachLocalMediaAndPublish();
      if (_left) return;
      _setStatus(CallEngineStatus.connected);
      _notifyParticipants();
      _statsTimer = Timer.periodic(
        _statsPollInterval,
        (_) => unawaited(_pollStats()),
      );
    } catch (_) {
      if (!mediaAdopted) await _quietly(capturedStream?.dispose);
      _setStatus(CallEngineStatus.failed);
      rethrow;
    }
  }

  Future<void> _openConnection() async {
    final sessionFuture = _api.createSession();
    final pcFuture = createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });
    final results = await Future.wait<Object?>(
      [sessionFuture, pcFuture],
      eagerError: true,
      cleanUp: _disposeOrphanedConnectResult,
    );
    final sessionId = results[0] as String;
    final pc = results[1] as RTCPeerConnection;
    if (_left) {
      await _closePeerConnection(pc);
      return;
    }
    pc.onTrack = _handleRemoteTrack;
    pc.onConnectionState = _handleConnectionState;
    _sessionId = sessionId;
    _pc = pc;
  }

  void _disposeOrphanedConnectResult(Object? value) {
    if (value is! RTCPeerConnection) return;
    unawaited(_closePeerConnection(value));
  }

  void _detachConnectionCallbacks(RTCPeerConnection? pc) {
    pc?.onTrack = null;
    pc?.onConnectionState = null;
  }

  Future<void> _closePeerConnection(RTCPeerConnection pc) => _quietly(() async {
    await pc.close();
    await pc.dispose();
  });

  Future<void> _discardLocalCapture(MediaStream? captured) async {
    final audio = _localAudioStream;
    final video = _localVideoStream;
    _localAudioStream = null;
    _localVideoStream = null;
    await _quietly(audio?.dispose);
    await _quietly(video?.dispose);
    await _quietly(captured?.dispose);
  }

  Future<void> _attachLocalMediaAndPublish() async {
    final pc = _pc;
    if (pc == null || !_isLiveConnection(pc)) return;
    _localAudioTransceiver = await pc.addTransceiver(
      track: _localAudioStream!.getAudioTracks().first,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendOnly),
    );
    if (!_isLiveConnection(pc)) return;
    final keyProvider = _keyProvider;
    if (keyProvider != null) {
      await _wrapSender(
        'local-audio',
        _localAudioTransceiver!.sender,
        keyProvider,
      );
    }
    if (!_isLiveConnection(pc)) return;

    _localVideoTransceiver = null;
    final videoTrack = _localVideoStream?.getVideoTracks().firstOrNull;
    final sendOnly = RTCRtpTransceiverInit(
      direction: TransceiverDirection.SendOnly,
    );
    final videoTransceiver = videoTrack == null
        ? await pc.addTransceiver(
            kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
            init: sendOnly,
          )
        : await pc.addTransceiver(track: videoTrack, init: sendOnly);
    if (!_isLiveConnection(pc)) return;
    _localVideoTransceiver = videoTransceiver;
    await _preferVideoCodecs(videoTransceiver);
    if (!_isLiveConnection(pc)) return;
    if (keyProvider != null) {
      await _wrapSender('local-video', videoTransceiver.sender, keyProvider);
    }
    if (!_isLiveConnection(pc)) return;
    _applyLocalTrackState();

    if (!_isLiveConnection(pc)) return;
    await _negotiationLock.run(_publishPendingTransceivers);
    if (!_isLiveConnection(pc)) return;
    await _reapplyVideoEncoding();
  }

  static const _disconnectGrace = Duration(seconds: 5);
  static const _maxReconnectAttempts = 3;
  static const _reconnectBaseDelay = Duration(seconds: 1);
  static const _reconnectMaxDelay = Duration(seconds: 4);

  Timer? _disconnectTimer;
  int _reconnectAttempts = 0;
  bool _reconnecting = false;

  @visibleForTesting
  void handleConnectionStateForTest(RTCPeerConnectionState state) =>
      _handleConnectionState(state);

  void _cancelDisconnectTimer() {
    _disconnectTimer?.cancel();
    _disconnectTimer = null;
  }

  void _handleConnectionState(RTCPeerConnectionState state) {
    if (_left) return;
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _cancelDisconnectTimer();
        _reconnectAttempts = 0;
        _setStatus(CallEngineStatus.connected);
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        _setStatus(CallEngineStatus.reconnecting);
        _disconnectTimer ??= Timer(_disconnectGrace, () {
          _disconnectTimer = null;
          unawaited(_reconnect());
        });
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        _cancelDisconnectTimer();
        unawaited(_reconnect());
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        _setStatus(CallEngineStatus.disconnected);
      case RTCPeerConnectionState.RTCPeerConnectionStateNew:
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        _setStatus(
          _reconnecting
              ? CallEngineStatus.reconnecting
              : CallEngineStatus.connecting,
        );
    }
  }

  Future<void> _reconnect() async {
    if (_left || _reconnecting) return;
    _reconnecting = true;
    _setStatus(CallEngineStatus.reconnecting);
    try {
      while (!_left) {
        _reconnectAttempts++;
        if (_reconnectAttempts > _maxReconnectAttempts) {
          _setStatus(CallEngineStatus.failed);
          return;
        }
        await Future<void>.delayed(
          backoffDelay(
            _reconnectAttempts,
            baseDelay: _reconnectBaseDelay,
            maxDelay: _reconnectMaxDelay,
          ),
        );
        if (_left) return;
        try {
          await _rejoin();
          if (_left) return;
          _notifyLocalStateChanged();
          return;
        } catch (e) {
          debugPrint('[Call] rejoin attempt $_reconnectAttempts failed: $e');
        }
      }
    } finally {
      _reconnecting = false;
    }
  }

  Future<void> _rejoin() async {
    final oldPc = _pc;
    _pc = null;
    _detachConnectionCallbacks(oldPc);
    _sessionId = null;
    _lastCounters = null;
    await _resetRemotesForRejoin();
    for (final label in const ['local-audio', 'local-video']) {
      await _frameCryptors.remove(label)?.dispose();
    }
    if (oldPc != null) await _closePeerConnection(oldPc);
    await _openConnection();
    if (_left) {
      final orphanedPc = _pc;
      _pc = null;
      _sessionId = null;
      _detachConnectionCallbacks(orphanedPc);
      if (orphanedPc != null) await _closePeerConnection(orphanedPc);
      return;
    }
    await _attachLocalMediaAndPublish();
    for (final remote in _remote.values.toList()) {
      unawaited(
        runBestEffort(
          () => _syncRemoteTracks(remote),
          label: 're-pull after rejoin for ${remote.id}',
        ),
      );
    }
    _notifyParticipants();
  }

  Future<void> _resetRemotesForRejoin() async {
    _midOwners.clear();
    for (final remote in _remote.values) {
      for (final name in remote.recvTransceivers.keys.toList()) {
        await _frameCryptors.remove('${remote.id}-$name')?.dispose();
      }
      await remote.resetTracks();
    }
  }

  Future<void> _publishPendingTransceivers() async {
    final pc = _pc;
    final sessionId = _sessionId;
    if (pc == null || sessionId == null || !_isLiveConnection(pc)) return;

    final localDescription = await _liveLocalOffer(pc);
    if (localDescription == null) return;

    final audioMid = await _currentMid(pc, _localAudioTransceiver!);
    if (!_isLiveConnection(pc)) return;
    final videoMid = await _currentMid(pc, _localVideoTransceiver!);
    if (!_isLiveConnection(pc)) return;

    await _pushTracksAndApplyAnswer(
      pc,
      sessionId: sessionId,
      offer: localDescription,
      tracks: [
        CfTrack.local(mid: audioMid, trackName: 'audio'),
        CfTrack.local(mid: videoMid, trackName: 'video'),
      ],
    );
  }

  Future<void> _pushTracksAndApplyAnswer(
    RTCPeerConnection pc, {
    required String sessionId,
    required RTCSessionDescription offer,
    required List<CfTrack> tracks,
  }) async {
    final result = await _api.pushLocalTracks(
      sessionId: sessionId,
      offer: _cfDescription(offer),
      tracks: tracks,
    );
    if (!_isLiveConnection(pc)) return;
    if (result.sessionDescription case final answer?) {
      await pc.setRemoteDescription(
        RTCSessionDescription(answer.sdp, answer.type),
      );
    }
  }

  static const _statsPollInterval = Duration(seconds: 3);

  Future<void> _pollStats() async {
    final pc = _pc;
    if (pc == null || _left) return;
    try {
      final counters = StatsCounters.fromReports(await pc.getStats());
      if (!_isLiveConnection(pc)) return;
      final previous = _lastCounters;
      _lastCounters = counters;
      if (previous == null) return;
      final changed = _classifier.observe(counters.sampleSince(previous));
      if (changed == null) return;
      await _reapplyVideoEncoding();
      _notifyParticipants();
      _notifyLocalStateChanged();
    } catch (_) {}
  }

  Future<void> _reapplyVideoEncoding() async {
    final sender = _localVideoTransceiver?.sender;
    if (sender == null || _localVideoStream == null) return;
    final limits = videoEncodingFor(_combinedQuality, lowDataMode: lowDataMode);
    final params = applyVideoEncodingLimits(sender.parameters, limits);
    await runBestEffort(
      () => sender.setParameters(params),
      label: 'apply video encoding limits',
    );
  }

  bool _left = false;

  @override
  Future<void> leave() async {
    if (_left) return;
    _left = true;
    _cancelDisconnectTimer();
    _statsTimer?.cancel();
    _statsTimer = null;
    _lastCounters = null;
    _setStatus(CallEngineStatus.disconnected);
    for (final remote in _remote.values) {
      await remote.resetTracks();
    }
    _remote.clear();
    _midOwners.clear();
    _notifyParticipants();

    for (final entry in _frameCryptors.entries) {
      await runBestEffort(
        entry.value.dispose,
        label: 'dispose cryptor ${entry.key} on leave',
      );
    }
    _frameCryptors.clear();
    if (_keyProvider case final keyProvider?) {
      await runBestEffort(
        keyProvider.dispose,
        label: 'dispose key provider on leave',
      );
    }
    _keyProvider = null;

    await _quietly(_localAudioStream?.dispose);
    await _quietly(_localVideoStream?.dispose);
    _localAudioStream = null;
    _localVideoStream = null;
    _localAudioTransceiver = null;
    _localVideoTransceiver = null;

    if (_pc case final pc?) await _closePeerConnection(pc);
    _pc = null;
    _sessionId = null;
    _api.close();
  }

  @override
  Future<void> setMicrophoneMuted(bool muted) async {
    _micMuted = muted;
    _applyLocalTrackState();
    _notifyParticipants();
  }

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    _cameraEnabled = enabled;
    _applyLocalTrackState();
    _notifyParticipants();
  }

  bool _frontCamera = true;

  @override
  Future<void> switchCamera() async {
    final track = _localVideoStream?.getVideoTracks().firstOrNull;
    if (track == null) return;
    _frontCamera = await Helper.switchCamera(track);
    _notifyParticipants();
  }

  bool _switchingToVideo = false;

  @override
  Future<void> switchToVideo() async {
    if (_kind == CallKind.video || _switchingToVideo) return;
    _switchingToVideo = true;
    try {
      await _switchToVideoOnce();
    } finally {
      _switchingToVideo = false;
    }
  }

  Future<void> _switchToVideoOnce() async {
    final captured = await navigator.mediaDevices.getUserMedia({
      'audio': false,
      'video': _videoConstraints,
    });
    final wrapper = await createLocalMediaStream('local_video');
    final capturedTracks = captured.getVideoTracks();
    final wasCameraEnabled = _cameraEnabled;
    var attached = false;
    try {
      for (final track in capturedTracks) {
        await wrapper.addTrack(track);
      }
      final pc = _pc;
      final sender = _localVideoTransceiver?.sender;
      if (pc == null || sender == null || !_isLiveConnection(pc)) return;
      _localVideoStream = wrapper;
      _cameraEnabled = true;
      _frontCamera = true;
      _applyLocalTrackState();
      await sender.replaceTrack(capturedTracks.first);
      final keyProvider = _keyProvider;
      if (_isLiveConnection(pc) && keyProvider != null) {
        await _wrapSender('local-video', sender, keyProvider);
      }
      attached = _isLiveConnection(pc);
      if (attached) _applyLocalTrackState();
    } finally {
      if (!attached) {
        if (identical(_localVideoStream, wrapper)) _localVideoStream = null;
        _cameraEnabled = wasCameraEnabled;
        await _quietly(wrapper.dispose);
        await _quietly(captured.dispose);
      }
    }
    if (!attached) return;
    _kind = CallKind.video;
    _notifyParticipants();
    await _reapplyVideoEncoding();
  }

  @override
  Map<String, Object?>? get localFociInfo {
    final sessionId = _sessionId;
    if (sessionId == null) return null;
    return {
      'sessionId': sessionId,
      'tracks': {
        'audio': 'audio',
        if (_localVideoTransceiver != null) 'video': 'video',
      },
      'audioMuted': _micMuted,
      'videoEnabled': _cameraEnabled,
      'encrypted': _keyProvider != null,
      'lowBandwidth': _classifier.current != CallQuality.good,
    };
  }

  @override
  void updateRemoteParticipant(
    VoipParticipantId id,
    Map<String, Object?> fociInfo,
  ) {
    if (_left) return;
    final remoteSessionId = fociInfo['sessionId'] as String?;
    if (remoteSessionId == null) return;
    final tracks =
        (fociInfo['tracks'] as Map?)?.cast<String, Object?>() ?? const {};
    final remote =
        _remote[id] ?? _RemoteParticipant(id: id, sessionId: remoteSessionId);
    _remote[id] = remote;
    final sessionChanged = remote.sessionId != remoteSessionId;
    remote
      ..sessionId = remoteSessionId
      ..advertisedTracks = tracks
      ..audioMuted = fociInfo['audioMuted'] as bool? ?? false
      ..videoEnabled = fociInfo['videoEnabled'] as bool? ?? false
      ..encrypted = fociInfo['encrypted'] == true;
    final lowBandwidth = fociInfo['lowBandwidth'] as bool? ?? false;
    if (remote.lowBandwidth != lowBandwidth) {
      remote.lowBandwidth = lowBandwidth;
      unawaited(_reapplyVideoEncoding());
    }
    unawaited(
      runBestEffort(() async {
        if (sessionChanged) await _dropRemoteMedia(remote);
        await _syncRemoteTracks(remote);
      }, label: 'sync remote tracks for $id'),
    );
    _notifyParticipants();
  }

  bool _isLiveRemote(_RemoteParticipant remote) =>
      !_left && identical(_remote[remote.id], remote);

  Future<void> _syncRemoteTracks(_RemoteParticipant remote) async {
    if (!_isLiveRemote(remote)) return;
    final toPull = planRemoteTracks(
      advertised: remote.advertisedTracks.keys,
      pulled: remote.pulledTrackNames,
      remoteVideoEnabled: remote.videoEnabled,
      remoteEncrypted: remote.encrypted,
      localEncrypted: _keyProvider != null,
    );
    if (toPull.isNotEmpty) await _pullTracks(remote, toPull);
  }

  Future<void> _closeRemoteTrackNamesLocked(
    _RemoteParticipant remote,
    List<String> names,
  ) async {
    final mids = <String>[];
    for (final name in names) {
      final transceiver = remote.recvTransceivers.remove(name);
      remote.pulledTrackNames.remove(name);
      await _frameCryptors.remove('${remote.id}-$name')?.dispose();
      remote.setStream(name, null);
      _midOwners.removeWhere(
        (_, owner) => owner.participant == remote.id && owner.trackName == name,
      );
      await _quietly(remote.adoptedStreams.remove(name)?.dispose);
      if (transceiver == null) continue;
      mids.add(transceiver.mid);
      _midOwners.remove(transceiver.mid);
    }
    _notifyParticipants();
    if (mids.isNotEmpty) await _closeTracks(mids);
  }

  Future<void> _dropRemoteMedia(_RemoteParticipant remote) =>
      _negotiationLock.run(
        () => _closeRemoteTrackNamesLocked(
          remote,
          {
            ...remote.pulledTrackNames,
            ...remote.recvTransceivers.keys,
          }.toList(),
        ),
      );

  Future<void> _pullTracks(
    _RemoteParticipant remote,
    List<String> toPull,
  ) async {
    if (_left) return;
    if (remote.pulling) {
      remote.resyncPending = true;
      return;
    }
    final pc = _pc;
    final sessionId = _sessionId;
    if (pc == null || sessionId == null) return;

    remote.pulling = true;
    try {
      await _negotiationLock.run(() async {
        if (!_isLiveConnection(pc)) return;
        await _pullTracksLocked(remote, toPull, pc, sessionId);
      });
    } finally {
      remote.pulling = false;
      if (remote.resyncPending) {
        remote.resyncPending = false;
        if (_isLiveRemote(remote)) {
          await _syncRemoteTracks(remote);
        }
      }
    }
  }

  Future<void> _pullTracksLocked(
    _RemoteParticipant remote,
    List<String> toPull,
    RTCPeerConnection pc,
    String sessionId,
  ) async {
    final result = await _api.pullRemoteTracks(
      sessionId: sessionId,
      tracks: toPull
          .map(
            (name) =>
                CfTrack.remote(sessionId: remote.sessionId, trackName: name),
          )
          .toList(),
    );
    if (!_isLiveConnection(pc)) return;

    for (final track in result.tracks) {
      final name = track.trackName;
      final mid = track.mid;
      if (name == null || track.hasError || mid == null || mid.isEmpty) {
        continue;
      }
      remote.pulledTrackNames.add(name);
      _midOwners[mid] = (participant: remote.id, trackName: name);
      unawaited(
        runBestEffort(
          () => _adoptExistingTrack(remote, name, mid),
          label: 'adopt already-arrived $name track for ${remote.id}',
        ),
      );
    }

    final offered = result.sessionDescription;
    if (!result.requiresImmediateRenegotiation || offered == null) {
      await _adoptRemoteTransceivers(remote, pc);
      return;
    }

    await pc.setRemoteDescription(
      RTCSessionDescription(offered.sdp, offered.type),
    );
    if (!_isLiveConnection(pc)) return;
    try {
      await _adoptRemoteTransceivers(remote, pc);
      if (!_isLiveConnection(pc)) return;
      final localDescription = await _liveLocalAnswer(pc);
      if (localDescription == null) return;
      await _api.renegotiate(
        sessionId: sessionId,
        offer: _cfDescription(localDescription),
      );
    } catch (_) {
      await _rollbackUnansweredOffer(pc, remote.id);
      rethrow;
    }
  }

  Future<void> _rollbackUnansweredOffer(
    RTCPeerConnection pc,
    VoipParticipantId id,
  ) async {
    final state = pc.signalingState;
    if (!_isLiveConnection(pc) ||
        state == null ||
        state == RTCSignalingState.RTCSignalingStateStable) {
      return;
    }
    debugPrint('[Call] pull for $id left signaling in $state; rolling back');
    await runBestEffort(
      () => pc.setLocalDescription(RTCSessionDescription('', 'rollback')),
      label: 'roll back unanswered offer for $id',
    );
  }

  Future<void> _adoptRemoteTransceivers(
    _RemoteParticipant remote,
    RTCPeerConnection pc,
  ) async {
    for (final transceiver in await pc.getTransceivers()) {
      if (!_isLiveConnection(pc)) return;
      final owner = _midOwners[transceiver.mid];
      if (owner == null || owner.participant != remote.id) continue;
      remote.recvTransceivers[owner.trackName] = transceiver;
      final label = '${remote.id}-${owner.trackName}';
      await runBestEffort(
        () => _wrapReceiver(label, transceiver.receiver),
        label: 'wrap receiver $label',
      );
    }
  }

  Future<void> _adoptExistingTrack(
    _RemoteParticipant remote,
    String trackName,
    String mid,
  ) async {
    bool stillWanted() =>
        remote.pulledTrackNames.contains(trackName) &&
        remote.streamFor(trackName) == null;

    if (remote.streamFor(trackName) != null) return;
    final pc = _pc;
    if (pc == null) return;
    for (final transceiver in await pc.getTransceivers()) {
      if (!_isLiveConnection(pc)) return;
      if (transceiver.mid != mid) continue;
      final track = transceiver.receiver.track;
      if (track == null) return;
      if (!stillWanted()) return;
      MediaStream? stream;
      try {
        stream = await createLocalMediaStream(
          'adopted_${remote.id}_$trackName',
        );
        await stream.addTrack(track);
      } catch (_) {
        await _quietly(stream?.dispose);
        rethrow;
      }
      if (!_isLiveConnection(pc) ||
          !stillWanted() ||
          remote.adoptedStreams.containsKey(trackName)) {
        await _quietly(stream.dispose);
        return;
      }
      remote.adoptedStreams[trackName] = stream;
      remote.setStream(trackName, stream);
      _notifyParticipants();
      return;
    }
  }

  void _handleRemoteTrack(RTCTrackEvent event) {
    final mid = event.transceiver?.mid;
    final owner = mid == null ? null : _midOwners[mid];
    if (owner == null) return;
    final remote = _remote[owner.participant];
    if (remote == null) return;

    remote.setStream(owner.trackName, event.streams.firstOrNull);
    _notifyParticipants();
  }

  @override
  void removeRemoteParticipant(VoipParticipantId id) {
    if (_left) return;
    final remote = _remote.remove(id);
    if (remote == null) return;
    unawaited(
      runBestEffort(
        () => _dropRemoteMedia(remote),
        label: 'close tracks for departed $id',
      ),
    );
    _notifyParticipants();
  }

  @override
  void dispose() {
    unawaited(
      leave().whenComplete(() {
        _statusController.close();
        _participantsController.close();
        _localStateController.close();
      }),
    );
  }
}

class _RemoteParticipant {
  final VoipParticipantId id;
  String sessionId;
  Map<String, Object?> advertisedTracks = const {};
  final Set<String> pulledTrackNames = {};
  final Map<String, RTCRtpTransceiver> recvTransceivers = {};
  final Map<String, MediaStream> adoptedStreams = {};
  MediaStream? audioStream;
  MediaStream? videoStream;
  bool audioMuted = false;
  bool videoEnabled = false;
  bool lowBandwidth = false;
  bool encrypted = false;

  bool pulling = false;
  bool resyncPending = false;

  _RemoteParticipant({required this.id, required this.sessionId});

  MediaStream? streamFor(String trackName) =>
      trackName == 'video' ? videoStream : audioStream;

  void setStream(String trackName, MediaStream? stream) {
    if (trackName == 'video') {
      videoStream = stream;
    } else {
      audioStream = stream;
    }
  }

  Future<void> resetTracks() async {
    for (final s in adoptedStreams.values) {
      await _quietly(s.dispose);
    }
    adoptedStreams.clear();
    recvTransceivers.clear();
    pulledTrackNames.clear();
    audioStream = null;
    videoStream = null;
    resyncPending = false;
  }

  CallEngineParticipant toParticipant() => CallEngineParticipant(
    id: id,
    isLocal: false,
    audioStream: audioStream,
    videoStream: videoStream,
    audioMuted: audioMuted,
    videoEnabled: videoEnabled,
    encrypted: encrypted,
    lowBandwidth: lowBandwidth,
  );
}
