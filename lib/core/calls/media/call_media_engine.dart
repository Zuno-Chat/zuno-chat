import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals, setEquals;
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../errors/best_effort.dart';
import '../../errors/caught_errors.dart';
import '../../platform/platform_capabilities.dart';
import '../call_engine.dart';
import '../models/call_engine_participant.dart';
import '../models/call_engine_status.dart';
import '../models/call_kind.dart';
import '../models/call_quality.dart';
import '../models/voip_participant_id.dart';
import '../module/calls_module.dart';
import 'call_connection.dart';
import 'call_encryption.dart';
import 'call_quality_policy.dart';
import 'local_media.dart';
import 'simulcast_layers.dart';
import 'webrtc_backend.dart';

typedef _Membership = ({
  Map<String, Object?> fociInfo,
  String? membershipEventId,
});

typedef _UnopenedUpdate = ({VoipParticipantId id, _Membership membership});

String _senderLabel(MediaKind kind) => 'local-${kind.name}';

String receiverLabel(VoipParticipantId id, MediaKind kind) =>
    '$id-${kind.name}';

class CallMediaEngine implements CallEngine {
  CallMediaEngine({
    required CallConnectionOpener connections,
    required CallSpec spec,
    required CallKind kind,
    this.lowDataMode = false,
    this._webRtc = const WebRtcBackend(),
    PlatformCapabilities? capabilities,
  }) : _connections = connections,
       _spec = spec,
       _injectedCapabilities = capabilities,
       _kind = kind,
       _media = LocalMedia(
         _webRtc,
         lowDataMode: lowDataMode,
         cameraEnabled: kind == CallKind.video,
       ) {
    _opening = connections.open(spec, _CoreHost(this));
    unawaited(_opening.then(_onOpened, onError: (Object _) {}));
  }

  final WebRtcBackend _webRtc;
  final PlatformCapabilities? _injectedCapabilities;
  final bool lowDataMode;
  CallKind _kind;
  final LocalMedia _media;

  final CallConnectionOpener _connections;
  final CallSpec _spec;
  late final Future<CallConnection> _opening;
  CallConnection? _connection;
  bool _left = false;
  bool _removed = false;

  Future<void>? _callAudioPrepared;
  Future<void>? _localMediaStarted;
  bool _sendingCamera = false;
  bool _inBackground = false;
  bool _switchingToVideo = false;
  Future<void> _cameraWork = Future<void>.value();

  CallEngineStatus _status = CallEngineStatus.connecting;
  final _statusController = StreamController<CallEngineStatus>.broadcast();
  final _participantsController =
      StreamController<List<CallEngineParticipant>>.broadcast();
  final _localStateController = StreamController<void>.broadcast();
  List<CallEngineParticipant>? _lastEmittedParticipants;

  final Map<VoipParticipantId, _Remote> _remotes = {};
  final List<_UnopenedUpdate> _unopened = [];
  final Map<(VoipParticipantId, MediaKind), RTCRtpReceiver> _receivers = {};
  final Set<MediaKind> _replacedSenders = {};

  late final _encryption = CallEncryption(
    _webRtc.frameCryptorFactory,
    onSendersChanged: _applyLocalTrackState,
  );

  static const _statsPollInterval = Duration(seconds: 3);
  Timer? _statsTimer;
  StatsCounters? _lastCounters;
  final _link = CallQualityClassifier();

  PlatformCapabilities get _capabilities =>
      _injectedCapabilities ?? ambientCapabilities;

  static const _localId = VoipParticipantId(userId: 'local', deviceId: 'local');

  void _onOpened(CallConnection connection) {
    if (_left) {
      unawaited(
        runBestEffort(
          connection.close,
          label: 'close a connection opened after leaving',
        ),
      );
      return;
    }
    _connection = connection;
    final unopened = List.of(_unopened);
    _unopened.clear();
    for (final (:id, :membership) in unopened) {
      _offerRemote(connection, id, membership);
    }
  }

  @override
  CallEngineStatus get status => _status;
  @override
  Stream<CallEngineStatus> get statusStream => _statusController.stream;

  @override
  List<CallEngineParticipant> get participants => [
    CallEngineParticipant(
      id: _localId,
      isLocal: true,
      audioStream: _media.microphoneStream,
      videoStream: _media.cameraStream,
      audioMuted: _media.microphoneMuted,
      videoEnabled: _media.cameraEnabled,
      encrypted: _encryption.canSend,
      frontCamera: _media.frontCamera,
    ),
    for (final remote in _remotes.values)
      CallEngineParticipant(
        id: remote.id,
        isLocal: false,
        audioStream: _shownStream(remote, MediaKind.audio),
        videoStream: _shownStream(remote, MediaKind.video),
        audioMuted: remote.audioMuted,
        videoEnabled: remote.videoEnabled,
        encrypted: _readable(remote.id, remote.membership.fociInfo),
        weakConnection:
            (remote.reported ?? CallQuality.good) != CallQuality.good,
        sendingMedia: _connection?.sendingMedia(remote.id) ?? false,
      ),
  ];

  MediaStream? _shownStream(_Remote remote, MediaKind kind) {
    final stream = remote.streams[kind];
    if (stream == null) return null;
    final receiver = _receivers[(remote.id, kind)];
    return _encryption.decrypts(receiverLabel(remote.id, kind), receiver)
        ? stream
        : null;
  }

  @override
  Stream<List<CallEngineParticipant>> get participantsStream =>
      _participantsController.stream;

  @override
  CallKind get kind => _kind;

  @override
  CallQuality get quality => _link.current;
  @override
  Stream<void> get localStateChangedStream => _localStateController.stream;

  @override
  Map<String, Object?>? get localFociInfo {
    final handle = _connection?.handle;
    if (handle == null) return null;
    return {
      ...handle,
      'audioMuted': _media.microphoneMuted,
      'videoEnabled': _sendingCamera,
      'encrypted': _encryption.canSend,
    };
  }

  void _notifyLocalStateChanged() {
    if (_localStateController.isClosed) return;
    _localStateController.add(null);
  }

  void _setStatus(CallEngineStatus status) {
    if (_removed &&
        status != CallEngineStatus.removed &&
        status != CallEngineStatus.disconnected) {
      return;
    }
    _status = status;
    if (_statusController.isClosed) return;
    _statusController.add(status);
  }

  void _reportStatus(CallEngineStatus status) {
    if (_left) return;
    if (status == CallEngineStatus.removed) _removed = true;
    _setStatus(status);
  }

  void _notifyParticipants() {
    if (_participantsController.isClosed) return;
    final snapshot = participants;
    if (listEquals(_lastEmittedParticipants, snapshot)) return;
    _lastEmittedParticipants = snapshot;
    _participantsController.add(snapshot);
  }

  @override
  Future<void> setOwnKey(int slot, Uint8List key) =>
      _changeOwnKeys(() => _encryption.setOwnKey(slot, key));

  @override
  Future<void> sendWithSlot(int slot) =>
      _changeOwnKeys(() => _encryption.sendWithSlot(slot));

  @override
  Future<void> setPeerKey(VoipParticipantId id, int slot, Uint8List key) =>
      _changePeerKeys(id, () => _encryption.setPeerKey(id, slot, key));

  @override
  Future<void> forgetPeer(VoipParticipantId id) =>
      _changePeerKeys(id, () => _encryption.forgetPeer(id));

  Future<void> _changeOwnKeys(Future<void> Function() change) async {
    if (_left) return;
    await change();
    if (_left) return;
    try {
      await _wrapLocalSenders();
    } finally {
      _applyLocalTrackState();
      _notifyParticipants();
      _notifyLocalStateChanged();
    }
  }

  Future<void> _changePeerKeys(
    VoipParticipantId peer,
    Future<void> Function() change,
  ) async {
    if (_left) return;
    await change();
    if (_left) return;
    await Future.wait([
      for (final MapEntry(key: (id, kind), value: receiver)
          in _receivers.entries.toList())
        if (id == peer) _wrapReceiverAfterKey(id, kind, receiver),
    ]);
    _notifyParticipants();
    _reofferRemotes();
  }

  RTCRtpSender? _currentSender(MediaKind kind) =>
      _replacedSenders.contains(kind) ? null : _connection?.sender(kind);

  bool _encrypts(MediaKind kind) =>
      _encryption.encrypts(_senderLabel(kind), _currentSender(kind));

  void _applyLocalTrackState() => _media.applyTrackState(
    microphoneEncrypted: _encrypts(MediaKind.audio),
    cameraEncrypted: _encrypts(MediaKind.video),
  );

  Future<void> _wrapLocalSenders() async {
    if (_left) return;
    await Future.wait([
      for (final kind in MediaKind.values)
        if (_currentSender(kind) case final sender?) _wrapSender(kind, sender),
    ]);
  }

  Future<void> _wrapSender(MediaKind kind, RTCRtpSender sender) =>
      _encryption.wrapSender(
        _senderLabel(kind),
        sender,
        stillWanted: () => !_left && identical(_currentSender(kind), sender),
      );

  bool _isAdopted(
    VoipParticipantId id,
    MediaKind kind,
    RTCRtpReceiver receiver,
  ) => !_left && _receivers[(id, kind)]?.receiverId == receiver.receiverId;

  Future<void> _wrapReceiver(
    VoipParticipantId id,
    MediaKind kind,
    RTCRtpReceiver receiver,
  ) => _encryption.wrapReceiver(
    id,
    receiverLabel(id, kind),
    receiver,
    stillWanted: () => _isAdopted(id, kind, receiver),
  );

  Future<void> _wrapReceiverAfterKey(
    VoipParticipantId id,
    MediaKind kind,
    RTCRtpReceiver receiver,
  ) async {
    try {
      await _wrapReceiver(id, kind, receiver);
    } catch (e, s) {
      if (_isAdopted(id, kind, receiver)) {
        reportCaught('wrap receiver after key', e, s);
      }
    }
  }

  Future<void> _adoptSender(MediaKind kind, RTCRtpSender sender) async {
    _replacedSenders.remove(kind);
    await _wrapSender(kind, sender);
    _applyLocalTrackState();
    if (kind == MediaKind.video) _setSendingCamera(_showsCamera(sender));
  }

  bool _showsCamera(RTCRtpSender sender) {
    final track = sender.track;
    final camera = _media.camera;
    return track != null &&
        camera != null &&
        track.id == camera.id &&
        _media.cameraEnabled;
  }

  Future<void> _adoptReceiver(
    VoipParticipantId id,
    MediaKind kind,
    RTCRtpReceiver receiver,
  ) async {
    if (_left) return;
    _receivers[(id, kind)] = receiver;
    await _wrapReceiver(id, kind, receiver);
    _notifyParticipants();
  }

  Future<void> _dropReceiver(VoipParticipantId id, MediaKind kind) async {
    _receivers.remove((id, kind));
    await _encryption.dropReceiver(receiverLabel(id, kind));
    _notifyParticipants();
  }

  void _setRemoteStream(
    VoipParticipantId id,
    MediaKind kind,
    MediaStream? stream,
  ) {
    final remote = _remotes[id];
    if (remote == null) return;
    if (stream == null) {
      remote.streams.remove(kind);
    } else {
      remote.streams[kind] = stream;
    }
    _notifyParticipants();
  }

  Future<void> _connectionReplaced(Future<void> Function() closeOld) async {
    _lastCounters = null;
    _replacedSenders.addAll(MediaKind.values);
    _receivers.clear();
    _applyLocalTrackState();
    try {
      await closeOld();
    } finally {
      await _encryption.forgetAll();
      for (final remote in _remotes.values) {
        remote.streams.clear();
      }
      _notifyParticipants();
    }
  }

  void _peerRating(VoipParticipantId id, CallQuality? rating) {
    final remote = _remotes[id];
    if (remote == null || remote.reported == rating) return;
    remote.reported = rating;
    _notifyParticipants();
  }

  LocalSend get _localSend {
    final microphone = _media.microphone;
    if (microphone == null) {
      throw StateError('Local media is not open, so there is nothing to send');
    }
    final camera = _media.camera;
    return (
      microphone: microphone,
      camera: camera,
      sendCamera: camera != null && _media.cameraEnabled && !_inBackground,
    );
  }

  Future<void> _publishLocalMedia(Future<bool> Function() publish) async {
    if (_localMediaStarted case final started?) await started;
    if (_left) return;
    await _serialCameraWork(() async {
      if (await publish()) await _reapplyVideoEncoding();
      await runBestEffort(
        _applyHeldCameraState,
        label: 'apply camera state after publishing',
      );
    });
  }

  Future<void> _applyHeldCameraState() async {
    try {
      await _applyCameraState();
    } on CameraRefused {
      _media.cameraEnabled = false;
      _notifyParticipants();
      _notifyLocalStateChanged();
    }
  }

  @override
  Future<void> startLocalMedia() async {
    if (_left) return;
    await _prepareCallAudio();
    if (_left) return;
    await _serialCameraWork(
      () => _media.open(
        withCamera: !_inBackground || _capabilities.cameraStopsInBackground,
      ),
    );
    _applyLocalTrackState();
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
  Future<void> ready() => _opening;

  @override
  Future<void> join() async {
    await _prepareCallAudio();
    try {
      var connection = await _opening;
      if (_left) return;
      final media = _localMediaStarted = startLocalMedia();
      try {
        await Future.wait<void>([connection.join(), media], eagerError: true);
      } on CallsRouteGone {
        if (_left) return;
        final reopened = await _reopenWithFreshProvider(connection);
        if (reopened == null) return;
        connection = reopened;
        await Future.wait<void>([connection.join(), media], eagerError: true);
      }
      if (_left) return;
      _notifyParticipants();
      _statsTimer = Timer.periodic(
        _statsPollInterval,
        (_) => unawaited(_pollStats()),
      );
    } catch (_) {
      if (_left) return;
      _setStatus(CallEngineStatus.failed);
      rethrow;
    }
  }

  Future<CallConnection?> _reopenWithFreshProvider(CallConnection stale) async {
    if (identical(_connection, stale)) _connection = null;
    final held = [
      for (final remote in _remotes.values)
        (id: remote.id, membership: remote.membership),
    ];
    _remotes.clear();
    _unopened.insertAll(0, held);
    await _connectionReplaced(
      () => runBestEffort(stale.close, label: 'close a stale connection'),
    );
    if (_left) return null;
    final fresh = await _connections.open(
      _spec,
      _CoreHost(this),
      rediscover: true,
    );
    _onOpened(fresh);
    return identical(_connection, fresh) ? fresh : null;
  }

  Future<void> _pollStats() async {
    final connection = _connection;
    if (connection == null || _left) return;
    final peerConnections = connection.peerConnections;
    if (peerConnections.isEmpty) return;
    bool live() =>
        !_left &&
        identical(_connection, connection) &&
        listEquals(connection.peerConnections, peerConnections);
    try {
      final perPeerConnection = await Future.wait([
        for (final pc in peerConnections) pc.getStats(),
      ]);
      final counters = StatsCounters.merged([
        for (final reports in perPeerConnection)
          StatsCounters.fromReports(reports),
      ]);
      if (!live()) return;
      connection.observeStats(perPeerConnection.expand((reports) => reports));
      final previous = _lastCounters;
      _lastCounters = counters;
      if (previous != null) {
        final changed = _link.observe(
          counters.linkSampleSince(previous, cameraSending: _sendingCamera),
        );
        if (changed != null) _notifyLocalStateChanged();
      }
      connection.sendRating(quality);
    } catch (e, s) {
      if (live()) reportCaught('poll call stats', e, s);
    }
  }

  Future<void> _reapplyVideoEncoding() async {
    final sender = _currentSender(MediaKind.video);
    if (sender == null || !_sendingCamera) return;
    final params = applySimulcastLayers(
      sender.parameters,
      simulcastLayersFor(lowDataMode: lowDataMode),
    );
    try {
      await sender.setParameters(params);
    } catch (e, s) {
      if (!_left && identical(_currentSender(MediaKind.video), sender)) {
        reportCaught('apply video encoding limits', e, s);
      }
    }
  }

  @override
  Future<void> leave() async {
    if (_left) return;
    _left = true;
    _statsTimer?.cancel();
    _statsTimer = null;
    _lastCounters = null;
    _setStatus(CallEngineStatus.disconnected);
    final connection = _connection;
    _connection = null;
    _remotes.clear();
    _unopened.clear();
    _receivers.clear();
    _applyLocalTrackState();
    if (connection != null) {
      await runBestEffort(connection.close, label: 'close the connection');
    }
    _notifyParticipants();
    await _encryption.dispose();
    await _media.close();
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
    if (_media.camera == null && _videoSlot != VideoSlot.none) return;
    await _media.switchCamera();
    _notifyParticipants();
  }

  @override
  Future<void> setAppInBackground(bool inBackground) async {
    if (_inBackground == inBackground) return;
    _inBackground = inBackground;
    await _serialCameraWork(_applyCameraState);
  }

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

  VideoSlot get _videoSlot => _connection?.videoSlot ?? VideoSlot.none;

  bool _stillReady(CallConnection connection) =>
      !_left &&
      identical(_connection, connection) &&
      connection.videoSlot == VideoSlot.ready;

  Future<void> _applyCameraState() async {
    if (_left) return;
    final connection = _connection;
    switch (_videoSlot) {
      case VideoSlot.none:
        return _applyCameraStateBeforePublishing();
      case VideoSlot.held:
        return;
      case VideoSlot.ready:
        final apply = !_media.cameraEnabled
            ? _cameraOff
            : _inBackground
            ? _pauseCamera
            : _cameraOn;
        try {
          await apply(connection!);
        } catch (_) {
          if (_stillReady(connection!)) rethrow;
        }
    }
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

  Future<void> _cameraOff(CallConnection connection) async {
    _setSendingCamera(false);
    if (!await connection.showVideo(null)) {
      if (_stillReady(connection)) _applyLocalTrackState();
      return;
    }
    await _media.stopCamera();
    _notifyParticipants();
  }

  Future<void> _pauseCamera(CallConnection connection) async {
    if (!await connection.showVideo(null)) return;
    _setSendingCamera(false);
    if (_capabilities.cameraStopsInBackground || _media.camera == null) return;
    await _media.stopCamera();
    _notifyParticipants();
  }

  Future<void> _cameraOn(CallConnection connection) async {
    if (_media.camera == null) {
      await _media.stopCamera();
      await _startCamera();
    }
    final camera = _media.camera;
    if (camera == null) return;
    if (!await connection.showVideo(camera)) return;
    _setSendingCamera(true);
    await _reapplyVideoEncoding();
    _notifyParticipants();
  }

  bool _readable(VoipParticipantId id, Map<String, Object?> fociInfo) =>
      fociInfo['encrypted'] == true && _encryption.holdsKeyFor(id);

  Set<MediaKind> _wantedKinds(
    VoipParticipantId id,
    Map<String, Object?> fociInfo,
  ) => _readable(id, fociInfo)
      ? {MediaKind.audio, if (fociInfo['videoEnabled'] == true) MediaKind.video}
      : const {};

  @override
  void updateRemoteParticipant(
    VoipParticipantId id,
    Map<String, Object?> fociInfo, {
    required String? membershipEventId,
  }) {
    if (_left) return;
    final membership = (
      fociInfo: fociInfo,
      membershipEventId: membershipEventId,
    );
    final connection = _connection;
    if (connection == null) {
      _unopened.add((id: id, membership: membership));
      return;
    }
    _offerRemote(connection, id, membership);
  }

  bool _updateRemote(
    CallConnection connection,
    VoipParticipantId id,
    _Membership membership,
    Set<MediaKind> wanted,
  ) => connection.updateRemote(
    id,
    membership.fociInfo,
    wanted,
    membershipEventId: membership.membershipEventId,
  );

  void _offerRemote(
    CallConnection connection,
    VoipParticipantId id,
    _Membership membership,
  ) {
    final wanted = _wantedKinds(id, membership.fociInfo);
    if (!_updateRemote(connection, id, membership, wanted)) return;
    (_remotes[id] ??= _Remote(id))
      ..membership = membership
      ..offered = wanted;
    _notifyParticipants();
  }

  void _reofferRemotes() {
    final connection = _connection;
    if (connection == null) return;
    for (final remote in _remotes.values.toList()) {
      final wanted = _wantedKinds(remote.id, remote.membership.fociInfo);
      if (setEquals(wanted, remote.offered)) continue;
      remote.offered = wanted;
      _updateRemote(connection, remote.id, remote.membership, wanted);
    }
  }

  @override
  void removeRemoteParticipant(VoipParticipantId id) {
    if (_left) return;
    _unopened.removeWhere((update) => update.id == id);
    if (_remotes.remove(id) == null) return;
    _connection?.removeRemote(id);
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

class _Remote {
  _Remote(this.id);

  final VoipParticipantId id;
  _Membership membership = (fociInfo: const {}, membershipEventId: null);
  Set<MediaKind> offered = const {};
  CallQuality? reported;
  final Map<MediaKind, MediaStream> streams = {};

  Map<String, Object?> get _foci => membership.fociInfo;
  bool get audioMuted => _foci['audioMuted'] == true;
  bool get videoEnabled => _foci['videoEnabled'] == true;
}

final class _CoreHost implements CallConnectionHost {
  _CoreHost(this._engine);

  final CallMediaEngine _engine;

  @override
  WebRtcBackend get webRtc => _engine._webRtc;

  @override
  LocalSend get localSend => _engine._localSend;

  @override
  bool get sendingCamera => _engine._sendingCamera;

  @override
  List<RTCRtpEncoding> get videoEncodings =>
      simulcastEncodingsFor(lowDataMode: _engine.lowDataMode);

  @override
  Future<void> publishLocalMedia(Future<bool> Function() publish) =>
      _engine._publishLocalMedia(publish);

  @override
  Future<void> adoptSender(MediaKind kind, RTCRtpSender sender) =>
      _engine._adoptSender(kind, sender);

  @override
  Future<void> adoptReceiver(
    VoipParticipantId id,
    MediaKind kind,
    RTCRtpReceiver receiver,
  ) => _engine._adoptReceiver(id, kind, receiver);

  @override
  Future<void> dropReceiver(VoipParticipantId id, MediaKind kind) =>
      _engine._dropReceiver(id, kind);

  @override
  void setRemoteStream(
    VoipParticipantId id,
    MediaKind kind,
    MediaStream? stream,
  ) => _engine._setRemoteStream(id, kind, stream);

  @override
  Future<void> connectionReplaced(Future<void> Function() closeOld) =>
      _engine._connectionReplaced(closeOld);

  @override
  void peerRating(VoipParticipantId id, CallQuality? rating) =>
      _engine._peerRating(id, rating);

  @override
  void reportStatus(CallEngineStatus status) => _engine._reportStatus(status);

  @override
  void handleChanged() => _engine._notifyLocalStateChanged();

  @override
  void remotesChanged() => _engine._notifyParticipants();
}
