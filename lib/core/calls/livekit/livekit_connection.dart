import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' show Client;
import 'package:protobuf/protobuf.dart' show InvalidProtocolBufferException;

import '../../async/serial_lock.dart';
import '../../errors/best_effort.dart';
import '../../errors/caught_errors.dart';
import '../media/call_connection.dart';
import '../media/quality_report.dart';
import '../media/reconnect_policy.dart';
import '../media/video_codec.dart';
import '../models/call_engine_status.dart';
import '../models/call_quality.dart';
import '../models/sfu_failures.dart';
import '../models/voip_participant_id.dart';
import '../module/calls_module.dart';
import 'livekit_remotes.dart';
import 'livekit_signal_client.dart';
import 'livekit_token_client.dart';
import 'livekit_transport.dart';
import 'proto/livekit_models.pb.dart';
import 'proto/livekit_rtc.pb.dart';

class LiveKitTrackRefused implements SfuRefusal {
  const LiveKitTrackRefused(this.reason);

  final RequestResponse_Reason reason;

  static const _permanent = {
    RequestResponse_Reason.NOT_ALLOWED,
    RequestResponse_Reason.UNSUPPORTED_TYPE,
    RequestResponse_Reason.INVALID_REQUEST,
  };

  @override
  bool get permanent => _permanent.contains(reason);

  bool get needsFullReconnect => reason == RequestResponse_Reason.QUEUED;

  @override
  String toString() => 'LiveKitTrackRefused: ${reason.name}';
}

class _Closed implements Exception {
  const _Closed();
}

enum _Phase { idle, joined, recovering, ended, closed }

enum _Resume { resumed, unreachable, refused }

enum _Loss { none, resume, full }

const _reliableChannel = '_reliable';

typedef _Announced = ({
  MediaKind kind,
  MediaStreamTrack track,
  String cid,
  List<RTCRtpEncoding>? encodings,
  TrackInfo info,
});

class _Published {
  _Published(this.cid, this.info, this.transceiver);

  final String cid;
  final TrackInfo info;
  final RTCRtpTransceiver transceiver;
  bool muted = false;

  String get sid => info.sid;
}

class _Session {
  _Session(this.publisher, this.subscriber);

  final LiveKitTransport publisher;
  final LiveKitTransport subscriber;
  final Map<MediaKind, _Published> published = {};
  final Map<String, Completer<TrackInfo>> pendingTracks = {};
  final Map<String, TrackInfo> confirmedTracks = {};
  RTCDataChannel? ratings;

  List<LiveKitTransport> get transports => [publisher, subscriber];

  void abandonPending() {
    publisher.abandon();
    final pending = pendingTracks.values.toList();
    pendingTracks.clear();
    for (final track in pending) {
      if (!track.isCompleted) {
        track.completeError(const LiveKitNegotiationAbandoned());
      }
    }
  }

  Future<void> dispose() async {
    abandonPending();
    final channel = ratings;
    ratings = null;
    if (channel != null) {
      channel.onMessage = null;
      await runBestEffort(channel.close, label: 'close the LiveKit data');
    }
    await Future.wait([publisher.dispose(), subscriber.dispose()]);
  }
}

class LiveKitConnection implements CallConnection {
  LiveKitConnection({
    required this._client,
    required this._spec,
    required this._host,
    this._httpClient,
    LiveKitSocketConnect? connect,
  }) : _signal = LiveKitSignalClient(connect: connect) {
    _responses = _signal.responses.listen(_onResponse);
    _lost = _signal.lost.listen((_) {
      _signalUp = false;
      _connectionLost();
    });
  }

  final Client _client;
  final CallSpec _spec;
  final CallConnectionHost _host;
  final http.Client? _httpClient;
  final LiveKitSignalClient _signal;
  late final StreamSubscription<SignalResponse> _responses;
  late final StreamSubscription<void> _lost;
  final _remotes = LiveKitRemotes();
  final _remoteWork = SerialLock();

  _Phase _phase = _Phase.idle;
  _Session? _session;
  bool _signalUp = false;
  Uri? _url;
  String? _identity;
  String? _ownSid;
  List<ICEServer> _iceServers = const [];
  bool _relayOnly = false;
  CallEngineStatus? _reported;
  bool _everConnected = false;
  bool _recovering = false;
  _Loss _pendingLoss = _Loss.none;
  final _budget = ReconnectBudget();
  final _grace = DisconnectGrace();

  static const _publishDeadline = Duration(seconds: 10);

  bool get _closed => _phase == _Phase.closed;

  bool get _ended => _phase == _Phase.ended || _closed;

  bool _isLive(_Session session) => !_closed && identical(_session, session);

  void _requireLive(_Session session) {
    if (!_isLive(session)) throw const _Closed();
  }

  bool _isReady(_Session session) =>
      _isLive(session) && _phase == _Phase.joined;

  @override
  VideoSlot get videoSlot => switch (_phase) {
    _Phase.idle => VideoSlot.none,
    _Phase.joined => VideoSlot.ready,
    _ => VideoSlot.held,
  };

  @override
  RTCRtpSender? sender(MediaKind kind) =>
      _session?.published[kind]?.transceiver.sender;

  @override
  List<RTCPeerConnection> get peerConnections => [
    if (_session case final session? when !_closed)
      for (final transport in session.transports) transport.pc,
  ];

  @override
  Map<String, Object?>? get handle => switch (_identity) {
    final identity? => {'identity': identity},
    null => null,
  };

  @override
  Future<void> join() async {
    final _Session session;
    try {
      session = await _openSession();
    } on _Closed {
      return;
    } on LiveKitSignalClosed {
      if (_closed) return;
      rethrow;
    } on CallRemovedException {
      _end(CallEngineStatus.removed);
      rethrow;
    }
    _phase = _Phase.joined;
    _reconcile();
    _evaluate(session);
    var publishing = false;
    try {
      await _host.publishLocalMedia(() {
        publishing = true;
        return _publishLocalTracks(session);
      });
    } catch (e, s) {
      if (publishing) _publishFailed(session, e, s);
    }
  }

  Future<_Session> _openSession() async {
    final grant = await fetchLiveKitGrant(
      _client,
      _spec,
      httpClient: _httpClient,
    );
    if (_closed) throw const _Closed();
    _responses.pause();
    try {
      final join = await _signal.join(grant.url, grant.token);
      if (_closed) {
        await runBestEffort(_signal.leave, label: 'leave a LiveKit room');
        throw const _Closed();
      }
      _url = grant.url;
      _iceServers = join.iceServers;
      _relayOnly =
          join.clientConfiguration.forceRelay == ClientConfigSetting.ENABLED;
      final session = await _openTransports(
        liveKitConfiguration(_iceServers, relayOnly: _relayOnly),
      );
      if (_closed) {
        await session.dispose();
        await runBestEffort(_signal.leave, label: 'leave a LiveKit room');
        throw const _Closed();
      }
      _session = session;
      _signalUp = true;
      _ownSid = join.participant.sid;
      final identity = join.participant.identity;
      final identityChanged = identity != _identity;
      _identity = identity;
      _applyParticipants(join.otherParticipants, ownIdentity: identity);
      if (identityChanged) _host.handleChanged();
      return session;
    } finally {
      _responses.resume();
    }
  }

  Future<_Session> _openTransports(Map<String, dynamic> configuration) async {
    Future<LiveKitTransport> open(SignalTarget target) => LiveKitTransport.open(
      _host.webRtc,
      target: target,
      configuration: configuration,
      send: _send,
    );
    final [publisher, subscriber] = await Future.wait([
      open(SignalTarget.PUBLISHER),
      open(SignalTarget.SUBSCRIBER),
    ], cleanUp: (transport) => unawaited(transport.dispose()));
    final session = _Session(publisher, subscriber);
    try {
      session.ratings = await publisher.pc.createDataChannel(
        _reliableChannel,
        RTCDataChannelInit()..ordered = true,
      );
    } catch (_) {
      await session.dispose();
      rethrow;
    }
    for (final transport in session.transports) {
      transport.onStateChanged = () => _onPeerState(session);
    }
    final pc = subscriber.pc;
    pc.onTrack = (event) => _onTrack(session, event);
    pc.onRemoveTrack = (stream, track) =>
        _onRemoveTrack(session, stream, track);
    pc.onDataChannel = (channel) => _onDataChannel(session, channel);
    return session;
  }

  bool _send(SignalRequest request) {
    if (_closed) return false;
    try {
      _signal.send(request);
      return true;
    } on StateError {
      return false;
    }
  }

  void _onResponse(SignalResponse response) {
    if (_closed) return;
    final session = _session;
    if (session == null) return;
    switch (response.whichMessage()) {
      case SignalResponse_Message.answer:
        session.publisher.answerArrived(response.answer);
      case SignalResponse_Message.offer:
        unawaited(_answerSubscriber(session, response.offer));
      case SignalResponse_Message.trickle:
        unawaited(_addCandidate(session, response.trickle));
      case SignalResponse_Message.update:
        _participantsUpdated(response.update.participants);
      case SignalResponse_Message.trackPublished:
        final published = response.trackPublished;
        session.confirmedTracks[published.cid] = published.track;
        session.pendingTracks.remove(published.cid)?.complete(published.track);
      case SignalResponse_Message.requestResponse:
        _requestRefused(session, response.requestResponse);
      case SignalResponse_Message.leave:
        _serverLeft(response.leave);
      default:
    }
  }

  Future<void> _answerSubscriber(
    _Session session,
    SessionDescription offer,
  ) async {
    try {
      await session.subscriber.answer(offer);
    } catch (e, s) {
      if (!_isLive(session)) return;
      reportCaught('answer the LiveKit subscriber offer', e, s);
      _connectionLost();
    }
  }

  Future<void> _addCandidate(_Session session, TrickleRequest trickle) async {
    final transport = trickle.target == SignalTarget.SUBSCRIBER
        ? session.subscriber
        : session.publisher;
    try {
      await transport.addRemoteCandidate(trickle.candidateInit);
    } catch (e, s) {
      if (_isLive(session)) reportCaught('add a LiveKit ICE candidate', e, s);
    }
  }

  void _participantsUpdated(List<ParticipantInfo> participants) {
    final identity = _identity;
    if (identity == null) return;
    _applyParticipants(participants, ownIdentity: identity);
    _reconcile();
  }

  void _applyParticipants(
    Iterable<ParticipantInfo> participants, {
    required String ownIdentity,
  }) {
    final (:sendingChanged, :departed) = _remotes.updateParticipants(
      participants,
      ownIdentity: ownIdentity,
    );
    for (final id in departed) {
      _host.peerRating(id, null);
    }
    if (sendingChanged) _host.remotesChanged();
  }

  void _requestRefused(_Session session, RequestResponse response) {
    if (response.reason == RequestResponse_Reason.OK ||
        !response.hasAddTrack()) {
      return;
    }
    final cid = response.addTrack.cid;
    if (response.reason == RequestResponse_Reason.QUEUED) {
      if (session.confirmedTracks[cid] case final known?) {
        session.pendingTracks.remove(cid)?.complete(known);
        return;
      }
    }
    session.pendingTracks
        .remove(cid)
        ?.completeError(LiveKitTrackRefused(response.reason));
  }

  void _serverLeft(LeaveRequest leave) {
    switch (leave) {
      case LeaveRequest(action: LeaveRequest_Action.RESUME):
        _connectionLost();
      case LeaveRequest(action: LeaveRequest_Action.RECONNECT) ||
          LeaveRequest(reason: DisconnectReason.PARTICIPANT_REMOVED):
        _connectionLost(full: true);
      default:
        _end(CallEngineStatus.failed);
    }
  }

  Future<bool> _publishLocalTracks(_Session session) async {
    if (!_isLive(session)) return false;
    final send = _host.localSend;
    final camera = send.camera;
    final announced = await Future.wait([
      if (!session.published.containsKey(MediaKind.audio))
        _announceTrack(session, MediaKind.audio, send.microphone),
      if (send.sendCamera &&
          camera != null &&
          !session.published.containsKey(MediaKind.video))
        _announceTrack(session, MediaKind.video, camera),
    ], eagerError: true);
    if (announced.isEmpty) return false;
    final added = [
      for (final track in announced)
        (kind: track.kind, sender: await _addTransceiver(session, track)),
    ];
    if (!_isLive(session)) throw const LiveKitNegotiationAbandoned();
    await Future.wait([
      for (final (:kind, :sender) in added) _host.adoptSender(kind, sender),
    ]);
    await session.publisher.offer();
    return _isLive(session);
  }

  Future<_Announced> _announceTrack(
    _Session session,
    MediaKind kind,
    MediaStreamTrack track,
  ) async {
    final cid = track.id;
    if (cid == null || !_isLive(session)) {
      throw const LiveKitNegotiationAbandoned();
    }
    final encodings = kind == MediaKind.video ? _host.videoEncodings : null;
    final info =
        session.confirmedTracks[cid] ??
        await _addTrack(session, cid, kind, encodings);
    return (
      kind: kind,
      track: track,
      cid: cid,
      encodings: encodings,
      info: info,
    );
  }

  Future<RTCRtpSender> _addTransceiver(
    _Session session,
    _Announced announced,
  ) async {
    final (:kind, :track, :cid, :encodings, :info) = announced;
    if (!_isLive(session)) throw const LiveKitNegotiationAbandoned();
    final transceiver = await session.publisher.pc.addTransceiver(
      track: track,
      init: RTCRtpTransceiverInit(
        direction: TransceiverDirection.SendOnly,
        sendEncodings: encodings,
      ),
    );
    if (!_isLive(session)) throw const LiveKitNegotiationAbandoned();
    session.published[kind] = _Published(cid, info, transceiver);
    return transceiver.sender;
  }

  Future<TrackInfo> _addTrack(
    _Session session,
    String cid,
    MediaKind kind,
    List<RTCRtpEncoding>? encodings,
  ) async {
    final video = kind == MediaKind.video;
    final layers = encodings == null ? null : _layersOf(encodings);
    final published = Completer<TrackInfo>();
    session.pendingTracks[cid] = published;
    try {
      final sent = _send(
        SignalRequest(
          addTrack: AddTrackRequest(
            cid: cid,
            name: kind.name,
            type: video ? TrackType.VIDEO : TrackType.AUDIO,
            source: video ? TrackSource.CAMERA : TrackSource.MICROPHONE,
            muted: false,
            encryption: Encryption_Type.GCM,
            disableRed: true,
            audioFeatures: video ? null : const [AudioTrackFeature.TF_NO_DTX],
            layers: layers,
            simulcastCodecs: video
                ? [
                    SimulcastCodec(
                      codec: sentVideoCodec.toLowerCase(),
                      cid: cid,
                      layers: layers,
                    ),
                  ]
                : null,
          ),
        ),
      );
      if (!sent) throw const LiveKitNegotiationAbandoned();
      return await published.future.timeout(_publishDeadline);
    } finally {
      if (identical(session.pendingTracks[cid], published)) {
        session.pendingTracks.remove(cid);
      }
    }
  }

  static List<VideoLayer> _layersOf(List<RTCRtpEncoding> encodings) => [
    for (final (index, encoding) in encodings.indexed)
      VideoLayer(
        quality: index == encodings.length - 1
            ? VideoQuality.HIGH
            : index == 0
            ? VideoQuality.LOW
            : VideoQuality.MEDIUM,
        bitrate: encoding.maxBitrate,
      ),
  ];

  void _publishFailed(_Session session, Object error, StackTrace stack) {
    if (!_isReady(session)) return;
    if (error is! LiveKitNegotiationAbandoned) {
      reportCaught('publish to LiveKit', error, stack);
    }
    if (error is LiveKitTrackRefused && error.permanent) {
      _end(CallEngineStatus.failed);
      return;
    }
    _connectionLost(
      full: error is LiveKitTrackRefused && error.needsFullReconnect,
    );
  }

  static bool _publishFailure(Object error) =>
      error is LiveKitNegotiationAbandoned ||
      error is LiveKitTrackRefused ||
      error is TimeoutException;

  @override
  Future<bool> showVideo(MediaStreamTrack? camera) async {
    final session = _session;
    if (session == null || !_isReady(session)) return false;
    final published = session.published[MediaKind.video];
    try {
      if (camera == null) return await _hideCamera(session, published);
      if (published == null) return await _publishCamera(session, camera);
      return await _showCamera(session, published, camera);
    } catch (e, s) {
      if (!_isReady(session)) return false;
      if (!_publishFailure(e)) rethrow;
      _publishFailed(session, e, s);
      return false;
    }
  }

  Future<bool> _hideCamera(_Session session, _Published? published) async {
    if (published == null) return true;
    await published.transceiver.sender.replaceTrack(null);
    if (!_isLive(session)) return false;
    _mute(published, true);
    return true;
  }

  Future<bool> _publishCamera(_Session session, MediaStreamTrack camera) async {
    final sender = await _addTransceiver(
      session,
      await _announceTrack(session, MediaKind.video, camera),
    );
    await _host.adoptSender(MediaKind.video, sender);
    await session.publisher.offer();
    return _isLive(session);
  }

  Future<bool> _showCamera(
    _Session session,
    _Published published,
    MediaStreamTrack camera,
  ) async {
    final sender = published.transceiver.sender;
    if (sender.track?.id != camera.id) {
      await sender.replaceTrack(camera);
      if (!_isLive(session)) return false;
    }
    _mute(published, false);
    await _host.adoptSender(MediaKind.video, sender);
    return _isLive(session);
  }

  void _mute(_Published published, bool muted) {
    if (published.muted == muted) return;
    if (_send(
      SignalRequest(
        mute: MuteTrackRequest(sid: published.sid, muted: muted),
      ),
    )) {
      published.muted = muted;
    }
  }

  @override
  bool updateRemote(
    VoipParticipantId id,
    Map<String, Object?> fociInfo,
    Set<MediaKind> wanted, {
    required String? membershipEventId,
  }) {
    if (_closed) return false;
    final identity = fociInfo['identity'];
    if (identity is! String || identity.isEmpty) return false;
    _remotes.setMember(id, identity, wanted);
    _reconcile();
    return true;
  }

  @override
  bool sendingMedia(VoipParticipantId id) => _remotes.sendingMedia(id);

  @override
  void removeRemote(VoipParticipantId id) {
    if (_closed) return;
    _remotes.removeMember(id);
    _reconcile();
  }

  void _reconcile() {
    final session = _session;
    if (session == null || _closed) return;
    final wanted = _remotes.wanted();
    if (_signalUp) {
      final (:subscribe, :unsubscribe) = _remotes.subscriptionChanges(wanted);
      _sendSubscription(subscribe, subscribe: true);
      _sendSubscription(unsubscribe, subscribe: false);
    }
    final (:detach, :attach) = _remotes.attachments(wanted);
    for (final slot in detach) {
      unawaited(_remoteWork.run(() => _detach(session, slot)));
    }
    for (final attachment in attach) {
      unawaited(_remoteWork.run(() => _attach(session, attachment)));
    }
  }

  void _sendSubscription(List<String> sids, {required bool subscribe}) {
    if (sids.isEmpty) return;
    final sent = _send(
      SignalRequest(
        subscription: UpdateSubscription(trackSids: sids, subscribe: subscribe),
      ),
    );
    if (sent) _remotes.subscriptionsSent(sids, subscribe: subscribe);
  }

  Future<void> _attach(_Session session, LiveKitAttachment attachment) async {
    final (:slot, :arrival) = attachment;
    bool attached() => _isLive(session) && _remotes.isAttached(slot, arrival);
    if (!attached()) return;
    try {
      await _host.adoptReceiver(slot.id, slot.kind, arrival.receiver);
    } catch (e, s) {
      if (attached()) reportCaught('wrap a LiveKit receiver', e, s);
    }
    if (!attached()) return;
    _host.setRemoteStream(slot.id, slot.kind, arrival.stream);
  }

  Future<void> _detach(_Session session, LiveKitSlot slot) async {
    if (!_isLive(session)) return;
    await runBestEffort(
      () => _host.dropReceiver(slot.id, slot.kind),
      label: 'drop a LiveKit receiver',
    );
    if (!_isLive(session)) return;
    _host.setRemoteStream(slot.id, slot.kind, null);
  }

  void _onTrack(_Session session, RTCTrackEvent event) {
    if (!_isLive(session)) return;
    final stream = event.streams.firstOrNull;
    final receiver = event.receiver ?? event.transceiver?.receiver;
    if (stream == null || receiver == null) return;
    final ids = parseLiveKitStreamId(stream.id, event.track.id);
    if (ids == null) return;
    _remotes.arrived(
      LiveKitArrival(
        participantSid: ids.participantSid,
        trackSid: ids.trackSid,
        receiver: receiver,
        stream: stream,
      ),
    );
    _reconcile();
  }

  void _onRemoveTrack(
    _Session session,
    MediaStream stream,
    MediaStreamTrack track,
  ) {
    if (!_isLive(session)) return;
    final ids = parseLiveKitStreamId(stream.id, track.id);
    if (ids == null) return;
    _remotes.departed(ids.trackSid);
    _reconcile();
  }

  void _onDataChannel(_Session session, RTCDataChannel channel) {
    if (!_isLive(session) || channel.label != _reliableChannel) return;
    channel.onMessage = (message) {
      if (_isLive(session)) _onData(message);
    };
  }

  void _onData(RTCDataChannelMessage message) {
    if (!message.isBinary) return;
    final DataPacket packet;
    try {
      packet = DataPacket.fromBuffer(message.binary);
    } on InvalidProtocolBufferException {
      return;
    }
    if (packet.whichValue() != DataPacket_Value.user ||
        packet.user.topic != qualityChannelName) {
      return;
    }
    final id = _remotes.memberWith(packet.participantIdentity);
    if (id == null) return;
    final String text;
    try {
      text = utf8.decode(packet.user.payload);
    } on FormatException {
      return;
    }
    if (decodeQualityReport(text) case final rating?) {
      _host.peerRating(id, rating);
    }
  }

  @override
  void observeStats(Iterable<StatsReport> reports) {}

  @override
  void sendRating(CallQuality rating) {
    final channel = _session?.ratings;
    if (channel == null ||
        channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }
    final packet = DataPacket(
      user: UserPacket(
        topic: qualityChannelName,
        payload: utf8.encode(encodeQualityReport(rating)),
      ),
    ).writeToBuffer();
    unawaited(
      runBestEffort(
        () => channel.send(RTCDataChannelMessage.fromBinary(packet)),
        label: 'send our call quality',
      ),
    );
  }

  @override
  bool carriesRatingsTo(VoipParticipantId id) => _remotes.hasMember(id);

  void _report(CallEngineStatus status) {
    if (_closed || _reported == status) return;
    _reported = status;
    _host.reportStatus(status);
  }

  void _end(CallEngineStatus status) {
    if (_ended) return;
    _phase = _Phase.ended;
    _grace.cancel();
    _session?.abandonPending();
    _report(status);
  }

  void _onPeerState(_Session session) {
    if (_isReady(session)) _evaluate(session);
  }

  bool _any(_Session session, RTCPeerConnectionState state) =>
      session.transports.any((transport) => transport.state == state);

  void _evaluate(_Session session) {
    if (_any(session, RTCPeerConnectionState.RTCPeerConnectionStateFailed)) {
      _grace.cancel();
      _connectionLost();
      return;
    }
    if (_any(
      session,
      RTCPeerConnectionState.RTCPeerConnectionStateDisconnected,
    )) {
      _report(CallEngineStatus.reconnecting);
      _grace.start(() {
        if (_isReady(session) &&
            _any(
              session,
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected,
            )) {
          _connectionLost();
        }
      });
      return;
    }
    _grace.cancel();
    if (session.transports.every(
      (transport) =>
          transport.state ==
          RTCPeerConnectionState.RTCPeerConnectionStateConnected,
    )) {
      _everConnected = true;
      _budget.refill();
      _report(CallEngineStatus.connected);
      return;
    }
    _report(
      _everConnected
          ? CallEngineStatus.reconnecting
          : CallEngineStatus.connecting,
    );
  }

  void _connectionLost({bool full = false}) {
    if (_phase != _Phase.joined && _phase != _Phase.recovering) return;
    if (_session == null) return;
    if (full) {
      _pendingLoss = _Loss.full;
    } else if (_pendingLoss == _Loss.none) {
      _pendingLoss = _Loss.resume;
    }
    if (_recovering) {
      _session?.abandonPending();
      return;
    }
    unawaited(_recover());
  }

  Future<void> _recover() async {
    _recovering = true;
    try {
      var full = false;
      while (!_ended) {
        _phase = _Phase.recovering;
        _grace.cancel();
        _session?.abandonPending();
        _report(CallEngineStatus.reconnecting);
        final delay = _budget.nextDelay();
        if (delay == null) {
          _end(CallEngineStatus.failed);
          return;
        }
        await Future<void>.delayed(delay);
        if (_ended) return;
        full = full || _pendingLoss == _Loss.full;
        _pendingLoss = _Loss.none;
        try {
          final outcome = full ? _Resume.refused : await _resume();
          if (outcome == _Resume.unreachable) continue;
          if (outcome == _Resume.refused) {
            full = true;
            await _fullReconnect();
          }
        } catch (e, s) {
          if (_ended) return;
          if (reconnectEndsOn(e) case final end?) {
            if (end.reported) reportCaught('rejoin LiveKit', e, s);
            _end(end.status);
            return;
          }
          if (!_expectedFailure(e)) reportCaught('rejoin LiveKit', e, s);
          full = true;
          continue;
        }
        if (_ended || _pendingLoss == _Loss.none) return;
      }
    } finally {
      _recovering = false;
    }
  }

  static bool _expectedFailure(Object error) =>
      error is LiveKitSignalClosed ||
      error is LiveKitNegotiationAbandoned ||
      error is _Closed ||
      isExpectedCallsFailure(error);

  Future<_Resume> _resume() async {
    final session = _session;
    final url = _url;
    final sid = _ownSid;
    if (session == null || url == null || sid == null) return _Resume.refused;
    final _Resume? reopened;
    _responses.pause();
    try {
      reopened = await _reopenSignal(session, url, sid);
    } finally {
      _responses.resume();
    }
    if (reopened != null) return reopened;
    try {
      await session.publisher.offer(iceRestart: true);
      await _host.publishLocalMedia(() => _republish(session));
    } catch (e, s) {
      _requireLive(session);
      if (e is LiveKitTrackRefused && e.permanent) rethrow;
      if (_pendingLoss != _Loss.none) return _Resume.unreachable;
      if (!_expectedFailure(e)) reportCaught('resume LiveKit', e, s);
      return _Resume.refused;
    }
    _requireLive(session);
    _reconcile();
    if (_isReady(session)) _evaluate(session);
    return _Resume.resumed;
  }

  Future<_Resume?> _reopenSignal(_Session session, Uri url, String sid) async {
    _signalUp = false;
    final ReconnectResponse reconnect;
    try {
      reconnect = await _signal.resume(url, sid);
    } on LiveKitSignalUnreachable {
      return _Resume.unreachable;
    } on LiveKitJoinRefused {
      return _Resume.refused;
    }
    _requireLive(session);
    _signalUp = true;
    _send(
      SignalRequest(
        syncState: SyncState(
          subscription: UpdateSubscription(
            trackSids: _remotes.resync(),
            subscribe: true,
          ),
          publishTracks: [
            for (final published in session.published.values)
              TrackPublishedResponse(cid: published.cid, track: published.info),
          ],
        ),
      ),
    );
    try {
      await _reconfigure(session, reconnect);
    } catch (e, s) {
      _requireLive(session);
      reportCaught('resume LiveKit', e, s);
      return _Resume.refused;
    }
    _requireLive(session);
    return null;
  }

  Future<void> _reconfigure(
    _Session session,
    ReconnectResponse reconnect,
  ) async {
    final relayOnly = reconnect.hasClientConfiguration()
        ? reconnect.clientConfiguration.forceRelay ==
              ClientConfigSetting.ENABLED
        : _relayOnly;
    if (reconnect.iceServers.isEmpty && relayOnly == _relayOnly) return;
    if (reconnect.iceServers.isNotEmpty) _iceServers = reconnect.iceServers;
    _relayOnly = relayOnly;
    final configuration = liveKitConfiguration(
      _iceServers,
      relayOnly: relayOnly,
    );
    for (final transport in session.transports) {
      await transport.pc.setConfiguration(configuration);
    }
  }

  Future<bool> _republish(_Session session) async {
    final published = await _publishLocalTracks(session);
    if (_isLive(session) && _pendingLoss == _Loss.none && !_ended) {
      _phase = _Phase.joined;
    }
    return published;
  }

  Future<void> _fullReconnect() async {
    final old = _session;
    _session = null;
    _signalUp = false;
    old?.abandonPending();
    _remotes.resetSession();
    for (final id in _remotes.members) {
      _host.peerRating(id, null);
    }
    await _host.connectionReplaced(() async => old?.dispose());
    if (_ended) throw const _Closed();
    final session = await _openSession();
    _reconcile();
    await _host.publishLocalMedia(() => _republish(session));
    _requireLive(session);
    _host.remotesChanged();
    if (_isReady(session)) _evaluate(session);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _phase = _Phase.closed;
    _signalUp = false;
    _grace.cancel();
    final session = _session;
    _session = null;
    session?.abandonPending();
    unawaited(_responses.cancel());
    unawaited(_lost.cancel());
    await runBestEffort(_signal.leave, label: 'leave the LiveKit room');
    if (session != null) await session.dispose();
    _remotes.clear();
  }
}
