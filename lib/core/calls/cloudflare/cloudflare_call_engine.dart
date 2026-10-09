import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show debugPrint, listEquals, visibleForTesting;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;

import '../../errors/backoff.dart';
import '../../errors/best_effort.dart';
import '../../platform/platform_capabilities.dart';
import '../call_engine.dart';
import '../models/call_engine_participant.dart';
import '../models/call_engine_status.dart';
import '../models/call_kind.dart';
import '../models/call_quality.dart';
import '../models/voip_participant_id.dart';
import 'call_quality_policy.dart';
import 'cloudflare_api_client.dart';
import 'local_media.dart';
import 'negotiation_lock.dart';
import 'opus_send_params.dart';
import 'remote_track_plan.dart';
import 'video_codec_preference.dart';
import 'webrtc_backend.dart';

CfSessionDescription _cfDescription(RTCSessionDescription description) =>
    CfSessionDescription(sdp: description.sdp!, type: description.type!);

RTCSessionDescription _remoteDescription(CfSessionDescription description) =>
    RTCSessionDescription(
      withOpusSendParams(description.sdp),
      description.type,
    );

class CloudflareCallEngine implements CallEngine {
  final CloudflareApiClient _api;
  final WebRtcBackend _webRtc;
  CallKind _kind;

  RTCPeerConnection? _pc;
  String? _sessionId;

  final LocalMedia _media;
  Future<void>? _callAudioPrepared;
  RTCRtpTransceiver? _localAudioTransceiver;
  RTCRtpTransceiver? _localVideoTransceiver;
  bool _sendingCamera = false;
  bool _inBackground = false;
  Future<void> _cameraWork = Future<void>.value();
  final Set<String> _sendingTrackNames = {};
  Timer? _firstMediaTimer;

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

  final Future<List<Map<String, Object?>>> _iceServers;
  final bool lowDataMode;

  Timer? _statsTimer;
  StatsCounters? _lastCounters;
  final _classifier = CallQualityClassifier();
  final _localStateController = StreamController<void>.broadcast();

  final _negotiationLock = NegotiationLock();

  bool _isLiveConnection(RTCPeerConnection pc) => !_left && identical(_pc, pc);

  CloudflareCallEngine({
    required Uri Function() baseUri,
    required Future<String> Function() authorization,
    required CallKind kind,
    Future<List<Map<String, Object?>>>? iceServers,
    this.lowDataMode = false,
    http.Client? httpClient,
    this._webRtc = const WebRtcBackend(),
    PlatformCapabilities? capabilities,
  }) : _injectedCapabilities = capabilities,
       _api = CloudflareApiClient(
         baseUri: baseUri,
         authorization: authorization,
         httpClient: httpClient,
       ),
       _iceServers = iceServers ?? Future.value(const []),
       _kind = kind,
       _media = LocalMedia(
         _webRtc,
         lowDataMode: lowDataMode,
         cameraEnabled: kind == CallKind.video,
       );

  final PlatformCapabilities? _injectedCapabilities;

  PlatformCapabilities get _capabilities =>
      _injectedCapabilities ?? ambientCapabilities;

  @override
  Future<void> setEncryptionKey(Uint8List key) async {
    final existingKeyProvider = _keyProvider;
    final hadAudioCryptor = _frameCryptors.containsKey('local-audio');
    final hadVideoCryptor = _frameCryptors.containsKey('local-video');
    final keyProvider =
        existingKeyProvider ??
        await _webRtc.frameCryptorFactory.createDefaultKeyProvider(
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

  void _applyLocalTrackState() => _media.applyTrackState(
    microphoneEncrypted: _frameCryptors.containsKey('local-audio'),
    cameraEncrypted: _frameCryptors.containsKey('local-video'),
  );

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
      final cryptor = await _webRtc.frameCryptorFactory
          .createFrameCryptorForRtpSender(
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

  Future<void> _preferVideoCodecs(RTCRtpTransceiver transceiver) async {
    final order = _capabilities.videoCodecOrder;
    if (order == null) return;
    await runBestEffort(() async {
      final supported = await _webRtc.getRtpSenderCapabilities('video');
      await transceiver.setCodecPreferences(
        orderVideoCodecs(supported.codecs ?? const [], preferred: order),
      );
    }, label: 'set video codec preferences');
  }

  Future<void> _wrapReceiver(String label, RTCRtpReceiver receiver) async {
    final keyProvider = _keyProvider;
    if (keyProvider == null || _frameCryptors.containsKey(label)) return;
    final cryptor = await _webRtc.frameCryptorFactory
        .createFrameCryptorForRtpReceiver(
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
      audioStream: _media.microphoneStream,
      videoStream: _media.cameraStream,
      audioMuted: _media.microphoneMuted,
      videoEnabled: _media.cameraEnabled,
      encrypted: _keyProvider != null,
      lowBandwidth: _classifier.current != CallQuality.good,
      frontCamera: _media.frontCamera,
    ),
    ..._remote.values.map((r) => r.toParticipant()),
  ];
  @override
  Stream<List<CallEngineParticipant>> get participantsStream =>
      _participantsController.stream;

  @override
  CallKind get kind => _kind;

  @override
  Future<void> get microphoneCaptured => _media.microphoneCaptured;

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
    if (!_isLiveConnection(pc)) return;
    if (current == null || current.sdp == null || current.type == null) return;

    try {
      await _closeTracksOrThrow(pc, sessionId, mids, force, current);
    } catch (e, s) {
      if (!_isLiveConnection(pc)) return;
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
    await pc.setRemoteDescription(_remoteDescription(offered));
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
    final offer = await pc.createOffer(const <String, dynamic>{});
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
  Future<void> startLocalMedia() async {
    if (_left) return;
    await _prepareCallAudio();
    await _serialCameraWork(_media.open);
    _notifyParticipants();
  }

  Future<void> _prepareCallAudio() => _callAudioPrepared ??= _armCallAudio();

  Future<void> _armCallAudio() async {
    if (_capabilities.callKit) {
      await runBestEffort(
        _webRtc.armSystemCallAudio,
        label: 'arm system call audio',
      );
    }
    if (_capabilities.callMuteByInputMixer) {
      await runBestEffort(
        () => _webRtc.setMicrophoneMuteMode(MicrophoneMuteMode.inputMixer),
        label: 'set microphone mute mode',
      );
    }
  }

  @override
  Future<void> join() async {
    await _prepareCallAudio();
    try {
      await Future.wait<void>([
        _openConnection(),
        startLocalMedia(),
      ], eagerError: true);
      if (_left) return;

      await _serialCameraWork(_publishLocalMedia);
      if (_left) return;
      _setStatus(CallEngineStatus.connected);
      _notifyParticipants();
      _statsTimer = Timer.periodic(
        _statsPollInterval,
        (_) => unawaited(_pollStats()),
      );
    } catch (_) {
      _setStatus(CallEngineStatus.failed);
      rethrow;
    }
  }

  Future<void> _openConnection() async {
    final sessionFuture = _api.createSession();
    final pcFuture = _iceServers.then(
      (servers) => _webRtc.createPeerConnection({
        'iceServers': servers,
        'sdpSemantics': 'unified-plan',
      }),
    );
    final results = await Future.wait<Object?>(
      [sessionFuture, pcFuture],
      eagerError: true,
      cleanUp: _disposeOrphanedConnectResult,
    );
    final sessionId = results[0] as String;
    final pc = results[1] as RTCPeerConnection;
    if (_left) {
      await _disposePeerConnection(pc);
      return;
    }
    pc.onTrack = _handleRemoteTrack;
    pc.onConnectionState = _handleConnectionState;
    _sessionId = sessionId;
    _pc = pc;
  }

  void _disposeOrphanedConnectResult(Object? value) {
    if (value is! RTCPeerConnection) return;
    unawaited(_disposePeerConnection(value));
  }

  void _detachConnectionCallbacks(RTCPeerConnection? pc) {
    pc?.onTrack = null;
    pc?.onConnectionState = null;
  }

  Future<void> _disposePeerConnection(RTCPeerConnection pc) =>
      quietly(pc.dispose);

  Future<void> _publishLocalMedia() async {
    await _attachLocalMediaAndPublish();
    await runBestEffort(
      _applyCameraState,
      label: 'apply camera state after publishing',
    );
  }

  Future<void> _attachLocalMediaAndPublish() async {
    final pc = _pc;
    if (pc == null || !_isLiveConnection(pc)) return;
    _localAudioTransceiver = await pc.addTransceiver(
      track: _media.microphone!,
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
    final camera = _media.camera;
    final videoTrack = camera != null && _media.cameraEnabled && !_inBackground
        ? camera
        : await _placeholderTrack() ?? camera;
    if (!_isLiveConnection(pc)) return;
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
    _setSendingCamera(
      videoTrack != null &&
          identical(videoTrack, camera) &&
          _media.cameraEnabled,
    );

    if (!_isLiveConnection(pc)) return;
    await _negotiationLock.run(_publishPendingTransceivers);
    if (!_isLiveConnection(pc)) return;
    _watchFirstMedia(pc);
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
    _firstMediaTimer?.cancel();
    _sendingTrackNames.clear();
    await _resetRemotesForRejoin();
    for (final label in const ['local-audio', 'local-video']) {
      await _frameCryptors.remove(label)?.dispose();
    }
    if (oldPc != null) await _disposePeerConnection(oldPc);
    await _openConnection();
    if (_left) {
      final orphanedPc = _pc;
      _pc = null;
      _sessionId = null;
      _detachConnectionCallbacks(orphanedPc);
      if (orphanedPc != null) await _disposePeerConnection(orphanedPc);
      return;
    }
    await _serialCameraWork(_publishLocalMedia);
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
    for (final track in result.tracks.where((t) => t.hasError)) {
      logCaught('publish ${track.trackName}', '${track.errorCode}');
    }
    if (!_isLiveConnection(pc)) return;
    if (result.sessionDescription case final answer?) {
      await pc.setRemoteDescription(_remoteDescription(answer));
    }
  }

  static const _statsPollInterval = Duration(seconds: 3);

  Future<void> _pollStats() async {
    final pc = _pc;
    if (pc == null || _left) return;
    try {
      final reports = await pc.getStats();
      final counters = StatsCounters.fromReports(reports);
      if (!_isLiveConnection(pc)) return;
      _noteSendingTracks(reports);
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

  static const _firstMediaPollStart = Duration(milliseconds: 250);
  static const _firstMediaPollMax = Duration(seconds: 2);
  static const _firstMediaDeadline = Duration(seconds: 20);
  static const _publishedTrackNames = ['audio', 'video'];

  void _watchFirstMedia(RTCPeerConnection pc) {
    _firstMediaTimer?.cancel();
    var delay = _firstMediaPollStart;
    var waited = Duration.zero;
    void schedule() {
      _firstMediaTimer = Timer(delay, () async {
        if (!_isLiveConnection(pc)) return;
        waited += delay;
        try {
          final reports = await pc.getStats();
          if (!_isLiveConnection(pc)) return;
          _noteSendingTracks(reports);
        } catch (_) {}
        final silent = [
          for (final name in _publishedTrackNames)
            if (!_sendingTrackNames.contains(name)) name,
        ];
        if (silent.isEmpty || !_isLiveConnection(pc)) return;
        if (waited >= _firstMediaDeadline) {
          for (final name in silent) {
            logCaught(
              'publish $name',
              'no media sent ${_firstMediaDeadline.inSeconds} s after '
                  'publishing, so the SFU will drop it',
            );
          }
          return;
        }
        delay = delay * 2 > _firstMediaPollMax ? _firstMediaPollMax : delay * 2;
        schedule();
      });
    }

    schedule();
  }

  void _noteSendingTracks(List<StatsReport> reports) {
    var changed = false;
    for (final report in reports) {
      if (report.type != 'outbound-rtp') continue;
      final kind = report.values['kind'];
      final bytesSent = report.values['bytesSent'];
      if (kind is! String || bytesSent is! num || bytesSent <= 0) continue;
      if (_publishedTrackNames.contains(kind) && _sendingTrackNames.add(kind)) {
        changed = true;
      }
    }
    if (changed) _notifyLocalStateChanged();
  }

  Future<void> _reapplyVideoEncoding() async {
    final sender = _localVideoTransceiver?.sender;
    if (sender == null || !_sendingCamera) return;
    final limits = videoEncodingFor(_combinedQuality, lowDataMode: lowDataMode);
    final params = applyVideoEncodingLimits(sender.parameters, limits);
    await runBestEffort(
      () => sender.setParameters(params),
      label: 'apply video encoding limits',
    );
  }

  bool _left = false;

  PlaceholderVideo? _placeholderVideo;
  bool _placeholderUnavailable = false;

  Future<MediaStreamTrack?> _placeholderTrack() async {
    if (_placeholderVideo case final placeholder?) return placeholder.track;
    if (_placeholderUnavailable) return null;
    try {
      _placeholderVideo = await _webRtc.createPlaceholderVideo();
    } catch (e) {
      logCaught('create placeholder video', e);
    }
    if (_left) {
      await _releasePlaceholderVideo();
    } else if (_placeholderVideo == null) {
      _placeholderUnavailable = true;
      logCaught(
        'placeholder video unavailable',
        'a video slot with no camera behind it expires on the SFU after 30 s',
      );
    }
    return _placeholderVideo?.track;
  }

  Future<void> _releasePlaceholderVideo() async {
    final placeholder = _placeholderVideo;
    _placeholderVideo = null;
    if (placeholder == null) return;
    await runBestEffort(
      () => _webRtc.releasePlaceholderVideo(placeholder),
      label: 'release placeholder video',
    );
  }

  @override
  Future<void> leave() async {
    if (_left) return;
    _left = true;
    _cancelDisconnectTimer();
    _statsTimer?.cancel();
    _statsTimer = null;
    _firstMediaTimer?.cancel();
    _firstMediaTimer = null;
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

    await _media.close();
    _localAudioTransceiver = null;
    _localVideoTransceiver = null;

    if (_pc case final pc?) await _disposePeerConnection(pc);
    await _releasePlaceholderVideo();
    _pc = null;
    _sessionId = null;
    _api.close();
  }

  @override
  Future<void> setMicrophoneMuted(bool muted) async {
    _media.microphoneMuted = muted;
    _applyLocalTrackState();
    _notifyParticipants();
  }

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    if (enabled && _kind == CallKind.voice) return switchToVideo();
    _media.cameraEnabled = enabled;
    _notifyParticipants();
    await _serialCameraWork(_applyCameraState);
  }

  @override
  Future<void> switchCamera() => _serialCameraWork(_switchCameraOnce);

  Future<void> _switchCameraOnce() async {
    if (_media.camera == null && _localVideoTransceiver != null) return;
    await _media.switchCamera();
    _notifyParticipants();
  }

  @override
  Future<void> setAppInBackground(bool inBackground) async {
    if (_inBackground == inBackground) return;
    _inBackground = inBackground;
    await _serialCameraWork(_applyCameraState);
  }

  bool _switchingToVideo = false;

  @override
  Future<void> switchToVideo() async {
    if (_kind == CallKind.video || _switchingToVideo) return;
    _switchingToVideo = true;
    try {
      await _serialCameraWork(_switchToVideoOnce);
    } finally {
      _switchingToVideo = false;
    }
  }

  Future<void> _switchToVideoOnce() async {
    if (_left) return;
    _media.cameraEnabled = true;
    try {
      await _applyCameraState();
    } catch (_) {
      _media.cameraEnabled = false;
      _setSendingCamera(false);
      await _media.stopCamera();
      _notifyParticipants();
      rethrow;
    }
    if (_left) return;
    _kind = CallKind.video;
    _notifyParticipants();
  }

  Future<void> _serialCameraWork(Future<void> Function() work) {
    final run = _cameraWork.then((_) => work());
    _cameraWork = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  void _setSendingCamera(bool sending) {
    if (_sendingCamera == sending) return;
    _sendingCamera = sending;
    _notifyLocalStateChanged();
  }

  Future<void> _applyCameraState() async {
    if (_left) return;
    final transceiver = _localVideoTransceiver;
    if (transceiver == null) return _applyCameraStateBeforePublishing();
    final pc = _pc;
    if (pc == null || !_isLiveConnection(pc)) return;
    final sender = transceiver.sender;
    if (!_media.cameraEnabled) return _cameraOff(pc, sender);
    if (_inBackground) return _pauseCamera(pc, sender);
    return _cameraOn(pc, sender);
  }

  Future<void> _applyCameraStateBeforePublishing() async {
    final cameraEnabled = _media.cameraEnabled;
    if (cameraEnabled && !_inBackground) {
      if (_media.camera != null) return;
      await _startCamera();
    } else {
      if (cameraEnabled && _capabilities.cameraStopsInBackground) return;
      await _media.stopCamera();
    }
    _notifyParticipants();
  }

  Future<void> _startCamera() async {
    try {
      await _media.startCamera();
    } catch (_) {
      _media.cameraEnabled = false;
      _notifyParticipants();
      rethrow;
    }
    _applyLocalTrackState();
  }

  Future<void> _cameraOff(RTCPeerConnection pc, RTCRtpSender sender) async {
    _setSendingCamera(false);
    final placeholder = await _placeholderTrack();
    if (!_isLiveConnection(pc)) return;
    if (placeholder == null) {
      _applyLocalTrackState();
      return;
    }
    if (sender.track?.id != placeholder.id) {
      await sender.replaceTrack(placeholder);
      if (!_isLiveConnection(pc)) return;
    }
    await _media.stopCamera();
    _notifyParticipants();
  }

  Future<void> _pauseCamera(RTCPeerConnection pc, RTCRtpSender sender) async {
    final placeholder = await _placeholderTrack();
    if (placeholder == null || !_isLiveConnection(pc)) return;
    _setSendingCamera(false);
    if (sender.track?.id != placeholder.id) {
      await sender.replaceTrack(placeholder);
      if (!_isLiveConnection(pc)) return;
    }
    if (_capabilities.cameraStopsInBackground || _media.camera == null) return;
    await _media.stopCamera();
    _notifyParticipants();
  }

  Future<void> _cameraOn(RTCPeerConnection pc, RTCRtpSender sender) async {
    if (_media.camera == null) {
      await _media.stopCamera();
      await _startCamera();
    }
    final camera = _media.camera;
    if (camera == null || !_isLiveConnection(pc)) return;
    if (sender.track?.id != camera.id) {
      await sender.replaceTrack(camera);
      if (!_isLiveConnection(pc)) return;
    }
    final keyProvider = _keyProvider;
    if (keyProvider != null) {
      await _wrapSender('local-video', sender, keyProvider);
      if (!_isLiveConnection(pc)) return;
    }
    _applyLocalTrackState();
    _setSendingCamera(true);
    await _releasePlaceholderVideo();
    await _reapplyVideoEncoding();
    _notifyParticipants();
  }

  @override
  Map<String, Object?>? get localFociInfo {
    final sessionId = _sessionId;
    if (sessionId == null) return null;
    return {
      'sessionId': sessionId,
      'tracks': {
        for (final name in _publishedTrackNames)
          if (_sendingTrackNames.contains(name)) name: name,
      },
      'audioMuted': _media.microphoneMuted,
      'videoEnabled': _sendingCamera,
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
    List<String> names, {
    bool closeOnSfu = true,
  }) async {
    final mids = <String>[];
    for (final name in names) {
      final transceiver = remote.recvTransceivers.remove(name);
      remote.pulledTrackNames.remove(name);
      await _frameCryptors.remove('${remote.id}-$name')?.dispose();
      remote.setStream(name, null);
      _midOwners.removeWhere(
        (_, owner) => owner.participant == remote.id && owner.trackName == name,
      );
      await quietly(remote.adoptedStreams.remove(name)?.dispose);
      if (transceiver == null) continue;
      mids.add(transceiver.mid);
      _midOwners.remove(transceiver.mid);
    }
    _notifyParticipants();
    if (closeOnSfu && mids.isNotEmpty) await _closeTracks(mids);
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

    final pulledMids = <String, String>{};
    for (final track in result.tracks) {
      final name = track.trackName;
      final mid = track.mid;
      if (name != null) _notePullError(remote, name, track.errorCode);
      if (name == null || track.hasError || mid == null || mid.isEmpty) {
        continue;
      }
      remote.pulledTrackNames.add(name);
      _midOwners[mid] = (participant: remote.id, trackName: name);
      pulledMids[name] = mid;
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

    try {
      await pc.setRemoteDescription(_remoteDescription(offered));
      if (!_isLiveConnection(pc)) return;
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
      if (_isLiveConnection(pc)) {
        await _forgetUnansweredPull(remote, pulledMids);
      }
      rethrow;
    }
  }

  void _notePullError(
    _RemoteParticipant remote,
    String trackName,
    String? errorCode,
  ) {
    if (errorCode == null) {
      remote.pullErrors.remove(trackName);
      return;
    }
    if (remote.pullErrors[trackName] == errorCode) return;
    remote.pullErrors[trackName] = errorCode;
    logCaught('pull $trackName from ${remote.id}', errorCode);
  }

  Future<void> _forgetUnansweredPull(
    _RemoteParticipant remote,
    Map<String, String> pulledMids,
  ) async {
    await _closeRemoteTrackNamesLocked(
      remote,
      pulledMids.keys.toList(),
      closeOnSfu: false,
    );
    await _closeTracks(pulledMids.values.toList(), force: true);
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
        stream = await _webRtc.createLocalMediaStream(
          'adopted_${remote.id}_$trackName',
        );
        await stream.addTrack(track);
      } catch (_) {
        await quietly(stream?.dispose);
        rethrow;
      }
      if (!_isLiveConnection(pc) ||
          !stillWanted() ||
          remote.adoptedStreams.containsKey(trackName)) {
        await quietly(stream.dispose);
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
  final Map<String, String> pullErrors = {};
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
      await quietly(s.dispose);
    }
    adoptedStreams.clear();
    recvTransceivers.clear();
    pulledTrackNames.clear();
    pullErrors.clear();
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
