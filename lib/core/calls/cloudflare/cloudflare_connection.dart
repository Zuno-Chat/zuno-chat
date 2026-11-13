import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' show Client;

import '../../async/serial_lock.dart';
import '../../errors/best_effort.dart';
import '../../errors/caught_errors.dart';
import '../../matrix/http/bearer_authorization.dart';
import '../media/call_connection.dart';
import '../media/quality_report.dart';
import '../media/reconnect_policy.dart';
import '../media/simulcast_layers.dart';
import '../models/call_engine_status.dart';
import '../models/call_quality.dart';
import '../models/voip_participant_id.dart';
import '../module/calls_module.dart';
import 'cloudflare_api_client.dart';
import 'cloudflare_ice_servers.dart';
import 'cloudflare_quality_channel.dart';
import 'cloudflare_routes.dart';
import 'placeholder_video.dart';
import 'remote_track_plan.dart';
import 'send_params.dart';

CfSessionDescription _cfDescription(RTCSessionDescription description) =>
    CfSessionDescription(sdp: description.sdp!, type: description.type!);

RTCSessionDescription _remoteDescription(CfSessionDescription description) =>
    RTCSessionDescription(withSendParams(description.sdp), description.type);

const _missingTrackCode = 'not_found_track_error';

class CloudflareConnection implements CallConnection {
  CloudflareConnection({
    required Uri Function() baseUri,
    required Future<String> Function() authorization,
    required this._spec,
    required this._host,
    Future<List<Map<String, Object?>>>? iceServers,
    http.Client? httpClient,
    this._placeholders = const PlaceholderVideoSource(),
  }) : _iceServers = iceServers ?? Future.value(const []) {
    _api = CloudflareApiClient(
      baseUri: baseUri,
      authorization: authorization,
      httpClient: httpClient,
      onRemoved: _onRemoved,
    );
  }

  CloudflareConnection.forClient(
    Client client, {
    required CallSpec spec,
    required CallConnectionHost host,
    http.Client? httpClient,
  }) : this(
         baseUri: () => cloudflareCallsBaseUri(client),
         authorization: () => bearerAuthorization(client),
         spec: spec,
         host: host,
         iceServers: resolveCloudflareIceServers(
           client,
           httpClient: httpClient,
         ),
         httpClient: httpClient,
       );

  late final CloudflareApiClient _api;
  final CallSpec _spec;
  final CallConnectionHost _host;
  final Future<List<Map<String, Object?>>> _iceServers;
  final PlaceholderVideoSource _placeholders;

  RTCPeerConnection? _pc;
  RTCPeerConnection? _brokenPc;
  bool _peerConnected = false;
  String? _sessionId;
  bool _closed = false;
  bool _removed = false;

  RTCRtpTransceiver? _localAudioTransceiver;
  RTCRtpTransceiver? _localVideoTransceiver;
  bool _published = false;
  final Set<String> _sendingTrackNames = {};
  Timer? _firstMediaTimer;

  final Map<VoipParticipantId, _RemoteParticipant> _remote = {};
  final Map<String, ({VoipParticipantId participant, String trackName})>
  _midOwners = {};

  late final _quality = CloudflareQualityChannel(onRating: _host.peerRating);
  final _negotiationLock = SerialLock();

  bool _isLiveConnection(RTCPeerConnection pc) =>
      !_closed && !_removed && identical(_pc, pc) && !identical(_brokenPc, pc);

  Future<void> _bestEffortOn(
    RTCPeerConnection pc,
    Future<void> Function() request, {
    required String label,
  }) async {
    try {
      await request();
    } catch (e, s) {
      if (_isLiveConnection(pc)) reportCaught(label, e, s);
    }
  }

  void _onRemoved() {
    if (_closed || _removed) return;
    _removed = true;
    _grace.cancel();
    _detachConnectionCallbacks(_pc);
    _host.reportStatus(CallEngineStatus.removed);
  }

  @override
  RTCRtpSender? sender(MediaKind kind) => switch (kind) {
    MediaKind.audio => _localAudioTransceiver?.sender,
    MediaKind.video => _localVideoTransceiver?.sender,
  };

  @override
  VideoSlot get videoSlot {
    if (_localVideoTransceiver == null) return VideoSlot.none;
    final pc = _pc;
    return pc != null && _isLiveConnection(pc)
        ? VideoSlot.ready
        : VideoSlot.held;
  }

  @override
  List<RTCPeerConnection> get peerConnections => [
    if (_pc case final pc? when _isLiveConnection(pc)) pc,
  ];

  static final _publishedTrackNames = [
    for (final kind in MediaKind.values) kind.name,
  ];

  @override
  Map<String, Object?>? get handle {
    final sessionId = _sessionId;
    if (sessionId == null) return null;
    return {
      'sessionId': sessionId,
      'tracks': {
        for (final name in _publishedTrackNames)
          if (_sendingTrackNames.contains(name)) name: name,
      },
      if (_quality.isPublished)
        'dataChannels': const {qualityChannelName: qualityChannelName},
    };
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

  Future<void> _closeTracks(List<String> mids) async {
    final pc = _pc;
    final sessionId = _sessionId;
    if (pc == null || sessionId == null || mids.isEmpty) return;
    if (!_isLiveConnection(pc)) return;
    await _bestEffortOn(
      pc,
      () => _api.closeTracks(sessionId: sessionId, mids: mids),
      label: 'closing tracks',
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
  Future<void> join() async {
    await _openConnection();
    if (_closed) return;
    await _host.publishLocalMedia(_attachLocalMediaAndPublish);
    if (_closed) return;
    for (final remote in _remote.values.toList()) {
      unawaited(
        runBestEffort(
          () => _syncRemoteTracks(remote),
          label: 'sync remote tracks',
        ),
      );
    }
    if (!_reconnecting) _host.reportStatus(CallEngineStatus.connected);
  }

  Future<void> _openConnection() async {
    final sessionFuture = _api.createSession(
      roomId: _spec.roomId,
      callId: _spec.callId,
    );
    final pcFuture = _iceServers.then(
      (servers) => _host.webRtc.createPeerConnection({
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
    if (_closed || _removed) {
      await _disposePeerConnection(pc);
      return;
    }
    pc.onTrack = _handleRemoteTrack;
    pc.onConnectionState = _handleConnectionState;
    _sessionId = sessionId;
    _pc = pc;
    _host.handleChanged();
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
      runBestEffort(pc.dispose, label: 'dispose the peer connection');

  Future<bool> _attachLocalMediaAndPublish() async {
    final pc = _pc;
    if (pc == null || !_isLiveConnection(pc)) return false;
    final audioTransceiver = await pc.addTransceiver(
      track: _host.localSend.microphone,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendOnly),
    );
    if (!_isLiveConnection(pc)) return false;
    _localAudioTransceiver = audioTransceiver;
    await _host.adoptSender(MediaKind.audio, audioTransceiver.sender);
    if (!_isLiveConnection(pc)) return false;

    _localVideoTransceiver = null;
    final send = _host.localSend;
    final videoTrack = send.sendCamera
        ? send.camera
        : await _placeholderTrack() ?? send.camera;
    if (!_isLiveConnection(pc)) return false;
    final sendOnly = RTCRtpTransceiverInit(
      direction: TransceiverDirection.SendOnly,
      sendEncodings: _host.videoEncodings,
    );
    final videoTransceiver = videoTrack == null
        ? await pc.addTransceiver(
            kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
            init: sendOnly,
          )
        : await pc.addTransceiver(track: videoTrack, init: sendOnly);
    if (!_isLiveConnection(pc)) return false;
    _localVideoTransceiver = videoTransceiver;
    await _host.adoptSender(MediaKind.video, videoTransceiver.sender);

    if (!_isLiveConnection(pc)) return false;
    try {
      await _negotiationLock.run(_publishPendingTransceivers);
    } catch (e, s) {
      if (!_isLiveConnection(pc)) return false;
      reportCaught('publish local tracks', e, s);
      _replaceBrokenSession(pc);
      return false;
    }
    if (!_isLiveConnection(pc)) return false;
    _published = true;
    _watchFirstMedia(pc);
    return true;
  }

  @override
  Future<bool> showVideo(MediaStreamTrack? camera) async {
    final pc = _pc;
    final sender = _localVideoTransceiver?.sender;
    if (pc == null || sender == null || !_isLiveConnection(pc)) return false;
    try {
      return camera == null
          ? await _showPlaceholder(pc, sender)
          : await _showCamera(pc, sender, camera);
    } catch (_) {
      if (_isLiveConnection(pc)) rethrow;
      return false;
    }
  }

  Future<bool> _showPlaceholder(
    RTCPeerConnection pc,
    RTCRtpSender sender,
  ) async {
    final placeholder = await _placeholderTrack();
    if (placeholder == null || !_isLiveConnection(pc)) return false;
    if (sender.track?.id != placeholder.id) {
      await sender.replaceTrack(placeholder);
      if (!_isLiveConnection(pc)) return false;
      await _host.adoptSender(MediaKind.video, sender);
      if (!_isLiveConnection(pc)) return false;
    }
    return true;
  }

  Future<bool> _showCamera(
    RTCPeerConnection pc,
    RTCRtpSender sender,
    MediaStreamTrack camera,
  ) async {
    if (sender.track?.id != camera.id) {
      await sender.replaceTrack(camera);
      if (!_isLiveConnection(pc)) return false;
    }
    await _host.adoptSender(MediaKind.video, sender);
    if (!_isLiveConnection(pc)) return false;
    await _releasePlaceholderVideo();
    return true;
  }

  void _openQualityChannelOnce() {
    final pc = _pc;
    final sessionId = _sessionId;
    if (pc == null ||
        sessionId == null ||
        !_peerConnected ||
        !_quality.claimPublish()) {
      return;
    }
    unawaited(_establishQualityChannel(pc, sessionId));
  }

  Future<void> _establishQualityChannel(
    RTCPeerConnection pc,
    String sessionId,
  ) async {
    await _negotiationLock.run(() async {
      if (!_isLiveConnection(pc)) return;
      var answering = false;
      try {
        final offer = await _api.establishDataChannels(sessionId: sessionId);
        if (!_isLiveConnection(pc)) return;
        if (offer != null) {
          answering = true;
          await _answerSfuOffer(pc, sessionId, offer);
          answering = false;
          if (!_isLiveConnection(pc)) return;
        }
        final published = (await _api.newDataChannels(
          sessionId: sessionId,
          channels: const [CfDataChannel.local(qualityChannelName)],
        )).firstOrNull;
        final id = published?.id;
        if (id == null) {
          throw CallsModuleException(
            'quality channel refused: ${published?.errorCode}',
          );
        }
        if (!_isLiveConnection(pc)) return;
        final channel = await _qualityChannel(pc, id);
        if (!_isLiveConnection(pc)) return;
        _quality.publish(channel);
      } catch (e, s) {
        if (!_isLiveConnection(pc)) return;
        _quality.giveUp();
        reportCaught('open the quality channel', e, s);
        if (answering) _replaceBrokenSession(pc);
        return;
      }
      _host.handleChanged();
      for (final remote in _remote.values.toList()) {
        unawaited(_subscribeToRatings(remote));
      }
    });
  }

  Future<RTCDataChannel> _qualityChannel(RTCPeerConnection pc, int id) =>
      pc.createDataChannel(
        qualityChannelName,
        RTCDataChannelInit()
          ..negotiated = true
          ..id = id,
      );

  Future<void> _closeAtCloudflare(
    RTCPeerConnection pc,
    String sessionId,
    int channelId,
  ) => _bestEffortOn(pc, () async {
    if (!_isLiveConnection(pc)) return;
    await _api.closeDataChannels(sessionId: sessionId, ids: [channelId]);
  }, label: 'close a quality subscription');

  @override
  void sendRating(CallQuality rating) {
    _quality.send(rating);
    _openQualityChannelOnce();
  }

  bool _carriesRatingsTo(VoipParticipantId id) =>
      _quality.isPublished && (_remote[id]?.advertisesRatings ?? false);

  void _ratingsRefused(
    VoipParticipantId peer,
    String peerSession,
    Object error, [
    StackTrace? stack,
  ]) {
    if (_quality.fail(peer, peerSession) && error != callRemovedErrorCode) {
      reportCaught('subscribe to call quality', error, stack);
    }
  }

  Future<void> _subscribeToRatings(_RemoteParticipant remote) async {
    final pc = _pc;
    final sessionId = _sessionId;
    final peer = remote.id;
    final peerSession = remote.sessionId;
    if (pc == null || sessionId == null || !_carriesRatingsTo(peer)) return;
    final claim = _quality.claim(peer, peerSession);
    if (claim == null) return;
    bool stillWanted() =>
        _isLiveConnection(pc) &&
        _isLiveRemote(remote) &&
        remote.sessionId == peerSession;
    try {
      await _negotiationLock.run(() async {
        if (!stillWanted()) return;
        final granted = (await _api.newDataChannels(
          sessionId: sessionId,
          channels: [
            CfDataChannel.remote(
              sessionId: peerSession,
              name: qualityChannelName,
            ),
          ],
        )).firstOrNull;
        final id = granted?.id;
        if (id == null) {
          if (stillWanted()) {
            _ratingsRefused(peer, peerSession, granted?.errorCode ?? 'none');
          }
          return;
        }
        if (!stillWanted()) return _closeAtCloudflare(pc, sessionId, id);
        final channel = await _qualityChannel(pc, id);
        if (!stillWanted()) {
          await closeQualityChannel(channel);
          return _closeAtCloudflare(pc, sessionId, id);
        }
        _quality.subscribe(
          peer,
          peerSession: peerSession,
          id: id,
          channel: channel,
        );
      });
    } catch (e, s) {
      if (_isLiveConnection(pc)) _ratingsRefused(peer, peerSession, e, s);
    } finally {
      _quality.release(peer, claim);
    }
  }

  Future<void> Function()? _dropRatings(VoipParticipantId peer) {
    final pc = _pc;
    final sessionId = _sessionId;
    final channelId = _quality.drop(peer);
    if (channelId == null || pc == null || sessionId == null) return null;
    return () => _negotiationLock.run(
      () => _closeAtCloudflare(pc, sessionId, channelId),
    );
  }

  final _grace = DisconnectGrace();
  final _budget = ReconnectBudget();
  bool _reconnecting = false;

  void _handleConnectionState(RTCPeerConnectionState state) {
    if (_closed || _removed) return;
    _peerConnected =
        state == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _grace.cancel();
        if (!_reconnecting) _budget.refill();
        _host.reportStatus(CallEngineStatus.connected);
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        _host.reportStatus(CallEngineStatus.reconnecting);
        final pc = _pc;
        _grace.start(() {
          if (identical(_pc, pc)) _replaceBrokenSession(pc);
        });
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        _grace.cancel();
        _replaceBrokenSession(_pc);
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        _host.reportStatus(CallEngineStatus.disconnected);
      case RTCPeerConnectionState.RTCPeerConnectionStateNew:
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        _host.reportStatus(
          _reconnecting
              ? CallEngineStatus.reconnecting
              : CallEngineStatus.connecting,
        );
    }
  }

  Future<void> _reconnect() async {
    if (_closed || _reconnecting) return;
    _reconnecting = true;
    _host.reportStatus(CallEngineStatus.reconnecting);
    try {
      while (!_closed && !_removed) {
        final delay = _budget.nextDelay();
        if (delay == null) {
          _host.reportStatus(CallEngineStatus.failed);
          return;
        }
        await Future<void>.delayed(delay);
        if (_closed) return;
        try {
          await _rejoin();
          if (_closed) return;
          final pc = _pc;
          if (pc == null || !_isLiveConnection(pc)) continue;
          if (_peerConnected) _budget.refill();
          _host.handleChanged();
          return;
        } catch (e, s) {
          if (_closed || _removed) return;
          if (reconnectEndsOn(e) case final end?) {
            if (end.reported) reportCaught('rejoin the call', e, s);
            if (end == ReconnectEnd.removed) return _onRemoved();
            _host.reportStatus(end.status);
            return;
          }
          reportCaught('rejoin the call', e, s);
        }
      }
    } finally {
      _reconnecting = false;
    }
  }

  void _replaceBrokenSession(RTCPeerConnection? pc) {
    _brokenPc = pc;
    _detachConnectionCallbacks(pc);
    _peerConnected = false;
    unawaited(_reconnect());
  }

  Future<void> _rejoin() async {
    final oldPc = _pc;
    _pc = null;
    _brokenPc = null;
    _peerConnected = false;
    _detachConnectionCallbacks(oldPc);
    _sessionId = null;
    await _quality.reset();
    _forgetLocalSenders();
    _firstMediaTimer?.cancel();
    _sendingTrackNames.clear();
    await _host.connectionReplaced(() async {
      if (oldPc != null) await _disposePeerConnection(oldPc);
    });
    await _resetRemotesForRejoin();
    await _openConnection();
    if (_closed) {
      final orphanedPc = _pc;
      _pc = null;
      _sessionId = null;
      _detachConnectionCallbacks(orphanedPc);
      if (orphanedPc != null) await _disposePeerConnection(orphanedPc);
      return;
    }
    await _host.publishLocalMedia(_attachLocalMediaAndPublish);
    for (final remote in _remote.values.toList()) {
      await _syncRemoteTracks(remote);
    }
    _host.remotesChanged();
  }

  void _forgetLocalSenders() {
    _localAudioTransceiver = null;
    _localVideoTransceiver = null;
    _published = false;
  }

  Future<void> _resetRemotesForRejoin() async {
    _midOwners.clear();
    for (final remote in _remote.values.toList()) {
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
        CfTrack.local(mid: audioMid, trackName: MediaKind.audio.name),
        CfTrack.local(mid: videoMid, trackName: MediaKind.video.name),
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
      reportCaught('publish ${track.trackName} rejected', '${track.errorCode}');
    }
    if (!_isLiveConnection(pc)) return;
    if (result.sessionDescription case final answer?) {
      await pc.setRemoteDescription(_remoteDescription(answer));
    }
  }

  @override
  void observeStats(Iterable<StatsReport> reports) =>
      _noteSendingTracks(reports);

  static const _firstMediaPoll = Duration(milliseconds: 100);
  static const _firstMediaDeadline = Duration(seconds: 20);

  void _watchFirstMedia(RTCPeerConnection pc) {
    _firstMediaTimer?.cancel();
    var waited = Duration.zero;
    void schedule() {
      _firstMediaTimer = Timer(_firstMediaPoll, () async {
        if (!_isLiveConnection(pc)) return;
        waited += _firstMediaPoll;
        await _bestEffortOn(pc, () async {
          final reports = await pc.getStats();
          if (!_isLiveConnection(pc)) return;
          _noteSendingTracks(reports);
        }, label: 'poll first media');
        final silent = [
          for (final name in _publishedTrackNames)
            if (!_sendingTrackNames.contains(name) && _expectsMedia(name)) name,
        ];
        if (silent.isEmpty || !_isLiveConnection(pc)) return;
        if (waited >= _firstMediaDeadline) {
          for (final name in silent) {
            reportCaught(
              'publish $name',
              'no media sent ${_firstMediaDeadline.inSeconds} s after '
                  'publishing, so the SFU will drop it',
            );
          }
          return;
        }
        schedule();
      });
    }

    schedule();
  }

  bool _expectsMedia(String trackName) =>
      trackName != MediaKind.video.name ||
      _host.sendingCamera ||
      !_placeholderUnavailable;

  void _noteSendingTracks(Iterable<StatsReport> reports) {
    if (_publishedTrackNames.every(_sendingTrackNames.contains)) return;
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
    if (changed) _host.handleChanged();
  }

  PlaceholderVideo? _placeholderVideo;
  bool _placeholderUnavailable = false;

  Future<MediaStreamTrack?> _placeholderTrack() async {
    if (_placeholderVideo case final placeholder?) return placeholder.track;
    if (_placeholderUnavailable) return null;
    try {
      _placeholderVideo = await _placeholders.create();
    } catch (e, s) {
      reportCaught('create placeholder video', e, s);
    }
    if (_closed) {
      await _releasePlaceholderVideo();
    } else if (_placeholderVideo == null) {
      _placeholderUnavailable = true;
    }
    return _placeholderVideo?.track;
  }

  Future<void> _releasePlaceholderVideo() async {
    final placeholder = _placeholderVideo;
    _placeholderVideo = null;
    if (placeholder == null) return;
    await runBestEffort(
      () => _placeholders.release(placeholder),
      label: 'release placeholder video',
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _grace.cancel();
    _firstMediaTimer?.cancel();
    _firstMediaTimer = null;
    final pc = _pc;
    _pc = null;
    _sessionId = null;
    await _quality.reset();
    _forgetLocalSenders();
    if (pc != null) await _disposePeerConnection(pc);
    for (final remote in _remote.values.toList()) {
      await remote.resetTracks();
    }
    _remote.clear();
    _midOwners.clear();
    await _releasePlaceholderVideo();
    _api.close();
  }

  @override
  bool updateRemote(
    VoipParticipantId id,
    Map<String, Object?> fociInfo,
    Set<MediaKind> wanted, {
    required String? membershipEventId,
  }) {
    if (_closed) return false;
    final remoteSessionId = fociInfo['sessionId'];
    if (remoteSessionId is! String) return false;
    final tracks = switch (fociInfo['tracks']) {
      final Map tracks => tracks.cast<String, Object?>(),
      _ => const <String, Object?>{},
    };
    final remote =
        _remote[id] ?? _RemoteParticipant(id: id, sessionId: remoteSessionId);
    _remote[id] = remote;
    final sessionChanged = remote.sessionId != remoteSessionId;
    if (sessionChanged) remote.pullFailures.clear();
    remote
      ..sessionId = remoteSessionId
      ..membershipEventId = membershipEventId
      ..advertisedTracks = tracks
      ..wanted = wanted
      ..advertisesRatings = switch (fociInfo['dataChannels']) {
        {qualityChannelName: _} => true,
        _ => false,
      };
    final closeDroppedRatings = sessionChanged || !remote.advertisesRatings
        ? _dropRatings(id)
        : null;
    unawaited(
      runBestEffort(() async {
        if (sessionChanged) await _dropRemoteMedia(remote);
        await _syncRemoteTracks(remote);
      }, label: 'sync remote tracks').then((_) async {
        await closeDroppedRatings?.call();
        await _subscribeToRatings(remote);
      }),
    );
    return true;
  }

  @override
  bool sendingMedia(VoipParticipantId id) =>
      _remote[id]?.advertisedTracks.isNotEmpty ?? false;

  bool _isLiveRemote(_RemoteParticipant remote) =>
      !_closed && identical(_remote[remote.id], remote);

  Future<void> _syncRemoteTracks(_RemoteParticipant remote) async {
    if (!_isLiveRemote(remote)) return;
    final toPull = planRemoteTracks(
      advertised: remote.advertisedTracks.keys,
      pulled: remote.pulledTrackNames,
      wanted: remote.wanted,
    );
    if (toPull.isNotEmpty) await _pullTracks(remote, toPull);
  }

  void _setStream(
    _RemoteParticipant remote,
    String trackName,
    MediaStream? stream,
  ) {
    if (stream == null) {
      remote.streams.remove(trackName);
    } else {
      remote.streams[trackName] = stream;
    }
    if (mediaKindOf(trackName) case final kind?) {
      _host.setRemoteStream(remote.id, kind, stream);
    }
  }

  Future<void> _closeRemoteTrackNamesLocked(
    _RemoteParticipant remote,
    List<String> names,
  ) async {
    final mids = <String>[];
    for (final name in names) {
      final transceiver = remote.recvTransceivers.remove(name);
      remote.pulledTrackNames.remove(name);
      if (mediaKindOf(name) case final kind?) {
        await _host.dropReceiver(remote.id, kind);
      }
      _setStream(remote, name, null);
      _midOwners.removeWhere(
        (_, owner) => owner.participant == remote.id && owner.trackName == name,
      );
      await _disposeAdoptedStream(remote.adoptedStreams.remove(name));
      if (transceiver == null) continue;
      mids.add(transceiver.mid);
      _midOwners.remove(transceiver.mid);
    }
    await _closeTracks(mids);
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
    if (_closed) return;
    if (remote.pulling) {
      remote.resyncPending = true;
      return;
    }
    final pc = _pc;
    final sessionId = _sessionId;
    if (pc == null || sessionId == null || !_published) return;

    remote.pulling = true;
    try {
      await _negotiationLock.run(() async {
        if (!_isLiveConnection(pc)) return;
        try {
          await _pullTracksLocked(remote, toPull, pc, sessionId);
        } catch (e, s) {
          if (!_isLiveConnection(pc)) return;
          reportCaught('pull remote tracks', e, s);
          _replaceBrokenSession(pc);
        }
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
            (name) => CfTrack.remote(
              sessionId: remote.sessionId,
              trackName: name,
              preferredRid: name == MediaKind.video.name ? fullLayerRid : null,
            ),
          )
          .toList(),
    );
    if (!_isLiveConnection(pc)) return;

    for (final track in result.tracks) {
      final name = track.trackName;
      final mid = track.mid;
      if (name != null) _notePullError(remote, name, track.errorCode);
      if (name == null || track.hasError || mid == null || mid.isEmpty) {
        continue;
      }
      remote.pulledTrackNames.add(name);
      _midOwners[mid] = (participant: remote.id, trackName: name);
      unawaited(
        _bestEffortOn(
          pc,
          () => _adoptExistingTrack(remote, name, mid, pc),
          label: 'adopt an already-arrived track',
        ),
      );
    }

    final offered = result.sessionDescription;
    if (!result.requiresImmediateRenegotiation || offered == null) {
      await _adoptRemoteTransceivers(remote, pc);
      return;
    }

    await _answerSfuOffer(
      pc,
      sessionId,
      offered,
      onApplied: () => _adoptRemoteTransceivers(remote, pc),
    );
  }

  Future<void> _answerSfuOffer(
    RTCPeerConnection pc,
    String sessionId,
    CfSessionDescription offer, {
    Future<void> Function()? onApplied,
  }) async {
    await pc.setRemoteDescription(_remoteDescription(offer));
    if (!_isLiveConnection(pc)) return;
    await onApplied?.call();
    if (!_isLiveConnection(pc)) return;
    final answer = await _liveLocalAnswer(pc);
    if (answer == null) return;
    await _api.renegotiate(sessionId: sessionId, offer: _cfDescription(answer));
  }

  void _notePullError(
    _RemoteParticipant remote,
    String trackName,
    String? errorCode,
  ) {
    if (errorCode == null) {
      remote.pullFailures.remove(trackName);
      return;
    }
    var failure = remote.pullFailures[trackName];
    if (failure == null || failure.code != errorCode) {
      failure = _PullFailure(errorCode, seenWith: remote.membershipEventId);
      remote.pullFailures[trackName] = failure;
    }
    if (failure.reported || !failure.isDefect(remote.membershipEventId)) {
      return;
    }
    failure.reported = true;
    reportCaught('pull $trackName', errorCode);
  }

  Future<void> _adoptRemoteTransceivers(
    _RemoteParticipant remote,
    RTCPeerConnection pc,
  ) async {
    for (final transceiver in await pc.getTransceivers()) {
      if (!_isLiveConnection(pc)) return;
      final owner = _midOwners[transceiver.mid];
      if (owner == null || owner.participant != remote.id) continue;
      final kind = mediaKindOf(owner.trackName);
      if (kind == null) continue;
      remote.recvTransceivers[owner.trackName] = transceiver;
      await _bestEffortOn(
        pc,
        () => _host.adoptReceiver(remote.id, kind, transceiver.receiver),
        label: 'wrap receiver',
      );
    }
  }

  Future<void> _adoptExistingTrack(
    _RemoteParticipant remote,
    String trackName,
    String mid,
    RTCPeerConnection pc,
  ) async {
    bool stillWanted() =>
        remote.pulledTrackNames.contains(trackName) &&
        remote.streams[trackName] == null;

    if (remote.streams[trackName] != null) return;
    for (final transceiver in await pc.getTransceivers()) {
      if (!_isLiveConnection(pc)) return;
      if (transceiver.mid != mid) continue;
      final track = transceiver.receiver.track;
      if (track == null) return;
      if (!stillWanted()) return;
      MediaStream? stream;
      try {
        stream = await _host.webRtc.createLocalMediaStream(
          'adopted_${remote.id}_$trackName',
        );
        await stream.addTrack(track);
      } catch (_) {
        await _disposeAdoptedStream(stream);
        rethrow;
      }
      if (!_isLiveConnection(pc) ||
          !stillWanted() ||
          remote.adoptedStreams.containsKey(trackName)) {
        await _disposeAdoptedStream(stream);
        return;
      }
      remote.adoptedStreams[trackName] = stream;
      _setStream(remote, trackName, stream);
      return;
    }
  }

  void _handleRemoteTrack(RTCTrackEvent event) {
    final mid = event.transceiver?.mid;
    final owner = mid == null ? null : _midOwners[mid];
    if (owner == null) return;
    final remote = _remote[owner.participant];
    if (remote == null) return;

    _setStream(remote, owner.trackName, event.streams.firstOrNull);
  }

  @override
  void removeRemote(VoipParticipantId id) {
    if (_closed) return;
    final remote = _remote.remove(id);
    if (remote == null) return;
    final closeDroppedRatings = _dropRatings(id);
    unawaited(
      runBestEffort(
        () => _dropRemoteMedia(remote),
        label: 'close tracks for a departed participant',
      ).then((_) => closeDroppedRatings?.call()),
    );
  }
}

Future<void> _disposeAdoptedStream(MediaStream? stream) =>
    runBestEffort(stream?.dispose, label: 'dispose an adopted stream');

class _PullFailure {
  _PullFailure(this.code, {required this.seenWith});

  final String code;
  final String? seenWith;
  bool reported = false;

  bool isDefect(String? latestMembership) => switch (code) {
    callRemovedErrorCode => false,
    _missingTrackCode =>
      latestMembership != null && latestMembership != seenWith,
    _ => true,
  };
}

class _RemoteParticipant {
  _RemoteParticipant({required this.id, required this.sessionId});

  final VoipParticipantId id;
  String sessionId;
  String? membershipEventId;
  Map<String, Object?> advertisedTracks = const {};
  Set<MediaKind> wanted = const {};
  bool advertisesRatings = false;
  final Set<String> pulledTrackNames = {};
  final Map<String, RTCRtpTransceiver> recvTransceivers = {};
  final Map<String, MediaStream> adoptedStreams = {};
  final Map<String, MediaStream> streams = {};
  final Map<String, _PullFailure> pullFailures = {};

  bool pulling = false;
  bool resyncPending = false;

  Future<void> resetTracks() async {
    for (final s in adoptedStreams.values) {
      await _disposeAdoptedStream(s);
    }
    adoptedStreams.clear();
    recvTransceivers.clear();
    pulledTrackNames.clear();
    pullFailures.clear();
    streams.clear();
    resyncPending = false;
  }
}
