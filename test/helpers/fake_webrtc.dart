import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:zuno/core/calls/cloudflare/webrtc_backend.dart';

class FakeTrack extends MediaStreamTrack {
  FakeTrack(this.kind, this.id, {this.journal});

  @override
  final String kind;
  @override
  final String id;
  final List<String>? journal;
  bool _enabled = true;
  bool stopped = false;

  @override
  bool get enabled => _enabled;
  @override
  set enabled(bool value) {
    if (value != _enabled) journal?.add('$id ${value ? 'on' : 'off'}');
    _enabled = value;
  }

  @override
  String? get label => id;
  @override
  bool? get muted => false;

  @override
  Future<void> stop() async => stopped = true;
  @override
  Future<void> dispose() async {}

  @override
  String toString() => 'FakeTrack($id)';
}

class FakeMediaStream extends MediaStream {
  FakeMediaStream(String id) : super(id, 'local');

  final tracks = <MediaStreamTrack>[];
  bool disposed = false;

  @override
  bool? get active => !disposed;
  @override
  Future<void> getMediaTracks() async {}
  @override
  Future<void> addTrack(
    MediaStreamTrack track, {
    bool addToNative = true,
  }) async => tracks.add(track);
  @override
  Future<void> removeTrack(
    MediaStreamTrack track, {
    bool removeFromNative = true,
  }) async => tracks.remove(track);
  @override
  List<MediaStreamTrack> getTracks() => List.of(tracks);
  @override
  List<MediaStreamTrack> getAudioTracks() =>
      tracks.where((t) => t.kind == 'audio').toList();
  @override
  List<MediaStreamTrack> getVideoTracks() =>
      tracks.where((t) => t.kind == 'video').toList();
  @override
  Future<void> dispose() async => disposed = true;
}

class FakeSender extends RTCRtpSender {
  FakeSender(this.senderId, this.track, {this.owner}) {
    if (track case final placed?) {
      placements.add((track: placed, enabled: placed.enabled));
    }
  }

  @override
  final String senderId;
  @override
  MediaStreamTrack? track;
  final FakePeerConnection? owner;
  final placements = <({MediaStreamTrack? track, bool enabled})>[];
  @override
  RTCRtpParameters parameters = RTCRtpParameters(
    encodings: [],
    degradationPreference: RTCDegradationPreference.BALANCED,
  );
  final appliedParameters = <RTCRtpParameters>[];
  final replacedTracks = <MediaStreamTrack?>[];

  @override
  Future<bool> setParameters(RTCRtpParameters parameters) async {
    this.parameters = parameters;
    appliedParameters.add(parameters);
    return true;
  }

  @override
  Future<void> replaceTrack(MediaStreamTrack? track) async {
    this.track = track;
    replacedTracks.add(track);
    placements.add((track: track, enabled: track?.enabled ?? false));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeReceiver extends RTCRtpReceiver {
  FakeReceiver(this.receiverId, this.track);

  @override
  final String receiverId;
  @override
  final MediaStreamTrack? track;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTransceiver extends RTCRtpTransceiver {
  FakeTransceiver({
    required this.mid,
    required this.sender,
    required this.receiver,
    this.direction,
  });

  @override
  final String mid;
  @override
  final FakeSender sender;
  @override
  final FakeReceiver receiver;
  final TransceiverDirection? direction;
  List<RTCRtpCodecCapability>? codecPreferences;

  @override
  Future<void> setCodecPreferences(List<RTCRtpCodecCapability> codecs) async =>
      codecPreferences = codecs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePeerConnection extends RTCPeerConnection {
  FakePeerConnection(this.configuration, {this.name = 'pc', this.journal});

  final Map<String, dynamic> configuration;
  final String name;
  final List<String>? journal;
  final rtpTransceivers = <FakeTransceiver>[];
  final localDescriptions = <RTCSessionDescription>[];
  final remoteDescriptions = <RTCSessionDescription>[];
  final pendingRemoteMids = <String, String>{};
  List<StatsReport> stats = [];
  Object? setRemoteDescriptionError;
  Object? createAnswerError;
  RTCSignalingState _signaling = RTCSignalingState.RTCSignalingStateStable;
  RTCSessionDescription? _local;
  var _offers = 0;
  var _answers = 0;
  bool closed = false;
  bool disposed = false;

  FakeTransceiver transceiverFor(String mid) =>
      rtpTransceivers.firstWhere((t) => t.mid == mid);

  void emitTrack(String mid, MediaStream stream) {
    final transceiver = transceiverFor(mid);
    onTrack?.call(
      RTCTrackEvent(
        streams: [stream],
        track: transceiver.receiver.track!,
        receiver: transceiver.receiver,
        transceiver: transceiver,
      ),
    );
  }

  @override
  RTCSignalingState? get signalingState => _signaling;
  @override
  RTCIceGatheringState? get iceGatheringState =>
      RTCIceGatheringState.RTCIceGatheringStateComplete;

  final offerConstraints = <Map<String, dynamic>?>[];

  @override
  Future<RTCSessionDescription> createOffer([
    Map<String, dynamic>? constraints,
  ]) async {
    offerConstraints.add(constraints);
    return RTCSessionDescription('local offer ${++_offers}', 'offer');
  }

  @override
  Future<RTCSessionDescription> createAnswer([
    Map<String, dynamic> constraints = const {},
  ]) async {
    if (createAnswerError case final error?) throw error;
    return RTCSessionDescription('local answer ${++_answers}', 'answer');
  }

  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {
    localDescriptions.add(description);
    _signaling = switch (description.type) {
      'offer' => RTCSignalingState.RTCSignalingStateHaveLocalOffer,
      _ => RTCSignalingState.RTCSignalingStateStable,
    };
    if (description.type != 'rollback') _local = description;
  }

  Completer<void>? localDescriptionGate;

  @override
  Future<RTCSessionDescription?> getLocalDescription() async {
    await localDescriptionGate?.future;
    return _local;
  }

  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    if (setRemoteDescriptionError case final error?) throw error;
    remoteDescriptions.add(description);
    if (description.type != 'offer') {
      _signaling = RTCSignalingState.RTCSignalingStateStable;
      return;
    }
    _signaling = RTCSignalingState.RTCSignalingStateHaveRemoteOffer;
    for (final MapEntry(key: mid, value: kind) in pendingRemoteMids.entries) {
      if (rtpTransceivers.any((t) => t.mid == mid)) continue;
      rtpTransceivers.add(
        FakeTransceiver(
          mid: mid,
          sender: FakeSender('recv-sender-$mid', null),
          receiver: FakeReceiver('receiver-$mid', FakeTrack(kind, 'r-$mid')),
          direction: TransceiverDirection.RecvOnly,
        ),
      );
    }
    pendingRemoteMids.clear();
  }

  @override
  Future<List<RTCRtpTransceiver>> getTransceivers() async =>
      List.of(rtpTransceivers);

  @override
  Future<RTCRtpTransceiver> addTransceiver({
    MediaStreamTrack? track,
    RTCRtpMediaType? kind,
    RTCRtpTransceiverInit? init,
  }) async {
    final mid = '${rtpTransceivers.length}';
    final transceiver = FakeTransceiver(
      mid: mid,
      sender: FakeSender('sender-$mid', track, owner: this),
      receiver: FakeReceiver('receiver-$mid', null),
      direction: init?.direction,
    );
    rtpTransceivers.add(transceiver);
    return transceiver;
  }

  @override
  Future<List<StatsReport>> getStats([MediaStreamTrack? track]) async => stats;

  @override
  Future<void> close() async => closed = true;
  @override
  Future<void> dispose() async {
    disposed = true;
    journal?.add('$name disposed');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeKeyProvider extends KeyProvider {
  FakeKeyProvider({this.journal});

  final List<String>? journal;
  final sharedKeys = <Uint8List>[];
  bool disposed = false;

  @override
  String get id => 'fake-key-provider';

  @override
  Future<void> setSharedKey({required Uint8List key, int index = 0}) async =>
      sharedKeys.add(key);

  @override
  Future<void> dispose() async {
    disposed = true;
    journal?.add('key provider disposed');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFrameCryptor extends FrameCryptor {
  FakeFrameCryptor(
    this.participantId, {
    this.failEnable = false,
    this.sender,
    this.journal,
  });

  @override
  final String participantId;
  final bool failEnable;
  final RTCRtpSender? sender;
  final List<String>? journal;
  bool isEnabled = false;
  bool disposed = false;

  @override
  Future<bool> setEnabled(bool enabled) async {
    if (failEnable) throw StateError('frame cryptor refused to start');
    isEnabled = enabled;
    return true;
  }

  @override
  Future<bool> get enabled async => isEnabled;
  @override
  Future<void> dispose() async {
    disposed = true;
    journal?.add('$participantId cryptor disposed');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFrameCryptorFactory implements FrameCryptorFactory {
  FakeFrameCryptorFactory({this.journal});

  final List<String>? journal;
  final keyProviders = <FakeKeyProvider>[];
  final cryptors = <FakeFrameCryptor>[];
  final failEnableFor = <String>{};
  Completer<void>? senderGate;

  Iterable<FakeFrameCryptor> get live => cryptors.where((c) => !c.disposed);

  Set<String> get liveLabels => {for (final c in live) c.participantId};

  @override
  Future<KeyProvider> createDefaultKeyProvider(
    KeyProviderOptions options,
  ) async {
    final provider = FakeKeyProvider(journal: journal);
    keyProviders.add(provider);
    return provider;
  }

  FakeFrameCryptor _cryptor(String label, {RTCRtpSender? sender}) {
    final cryptor = FakeFrameCryptor(
      label,
      failEnable: failEnableFor.contains(label),
      sender: sender,
      journal: journal,
    );
    cryptors.add(cryptor);
    return cryptor;
  }

  @override
  Future<FrameCryptor> createFrameCryptorForRtpSender({
    required String participantId,
    required RTCRtpSender sender,
    required Algorithm algorithm,
    required KeyProvider keyProvider,
  }) async {
    await senderGate?.future;
    if (sender is FakeSender && (sender.owner?.disposed ?? false)) {
      throw StateError('peerConnection not found');
    }
    return _cryptor(participantId, sender: sender);
  }

  @override
  Future<FrameCryptor> createFrameCryptorForRtpReceiver({
    required String participantId,
    required RTCRtpReceiver receiver,
    required Algorithm algorithm,
    required KeyProvider keyProvider,
  }) async => _cryptor(participantId);
}

class FakeWebRtcBackend implements WebRtcBackend {
  final journal = <String>[];
  final peerConnections = <FakePeerConnection>[];
  final captureConstraints = <Map<String, dynamic>>[];
  final captures = <FakeMediaStream>[];
  final streams = <FakeMediaStream>[];
  late final cryptors = FakeFrameCryptorFactory(journal: journal);
  final muteModes = <({MicrophoneMuteMode mode, int capturesBefore})>[];
  final audioArms = <({int capturesBefore, int connectionsBefore})>[];
  Object? captureError;
  final adoptErrors = <String, Object>{};
  Completer<void>? captureGate;
  int cameraSwitches = 0;
  var _tracks = 0;

  FakePeerConnection get pc => peerConnections.last;

  @override
  Future<RTCPeerConnection> createPeerConnection(
    Map<String, dynamic> configuration,
  ) async {
    final pc = FakePeerConnection(
      configuration,
      name: 'pc${peerConnections.length + 1}',
      journal: journal,
    );
    peerConnections.add(pc);
    return pc;
  }

  @override
  Future<void> setMicrophoneMuteMode(MicrophoneMuteMode mode) async {
    muteModes.add((mode: mode, capturesBefore: captureConstraints.length));
  }

  @override
  Future<void> armSystemCallAudio() async {
    audioArms.add((
      capturesBefore: captureConstraints.length,
      connectionsBefore: peerConnections.length,
    ));
  }

  @override
  Future<MediaStream> getUserMedia(Map<String, dynamic> constraints) async {
    captureConstraints.add(constraints);
    await captureGate?.future;
    if (captureError case final error?) throw error;
    final stream = FakeMediaStream('capture-${captures.length + 1}');
    if (constraints['audio'] == true) {
      stream.tracks.add(
        FakeTrack('audio', 'mic-${++_tracks}', journal: journal),
      );
    }
    if (constraints['video'] is Map) {
      stream.tracks.add(
        FakeTrack('video', 'camera-${++_tracks}', journal: journal),
      );
    }
    captures.add(stream);
    return stream;
  }

  @override
  Future<MediaStream> createLocalMediaStream(String label) async {
    if (adoptErrors[label] case final error?) throw error;
    final stream = FakeMediaStream(label);
    streams.add(stream);
    return stream;
  }

  bool placeholderAvailable = true;
  final placeholders = <PlaceholderVideo>[];
  final releasedPlaceholders = <PlaceholderVideo>[];

  @override
  Future<PlaceholderVideo?> createPlaceholderVideo() async {
    if (!placeholderAvailable) return null;
    final placeholder = (
      stream: FakeMediaStream('placeholder-${placeholders.length + 1}'),
      track: FakeTrack('video', 'black-${++_tracks}'),
    );
    placeholders.add(placeholder);
    return placeholder;
  }

  @override
  Future<void> releasePlaceholderVideo(PlaceholderVideo placeholder) async {
    releasedPlaceholders.add(placeholder);
  }

  @override
  Future<RTCRtpCapabilities> getRtpSenderCapabilities(String kind) async =>
      RTCRtpCapabilities(
        codecs: [
          for (final mime in ['video/AV1', 'video/H264', 'video/VP8'])
            RTCRtpCodecCapability(clockRate: 90000, mimeType: mime),
        ],
      );

  @override
  FrameCryptorFactory get frameCryptorFactory => cryptors;

  @override
  Future<bool> switchCamera(MediaStreamTrack track) async {
    cameraSwitches++;
    return false;
  }
}
