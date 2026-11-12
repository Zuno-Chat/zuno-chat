import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:zuno/core/calls/media/webrtc_backend.dart';

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
  bool get closed => owner?.disposed ?? false;
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

  Completer<void>? replaceGate;

  @override
  Future<void> replaceTrack(MediaStreamTrack? track) async {
    await replaceGate?.future;
    if (closed) throw StateError('peerConnection is null');
    this.track = track;
    replacedTracks.add(track);
    placements.add((track: track, enabled: track?.enabled ?? false));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeReceiver extends RTCRtpReceiver {
  FakeReceiver(this.receiverId, this.track, {this.owner});

  @override
  final String receiverId;
  @override
  final MediaStreamTrack? track;
  final FakePeerConnection? owner;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTransceiver extends RTCRtpTransceiver {
  FakeTransceiver({
    required this.mid,
    required this.sender,
    required this.receiver,
    this.direction,
    this.sendEncodings,
  });

  @override
  final String mid;
  @override
  final FakeSender sender;
  @override
  final FakeReceiver receiver;
  final TransceiverDirection? direction;
  final List<RTCRtpEncoding>? sendEncodings;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeDataChannel extends RTCDataChannel {
  FakeDataChannel(this._label, this._id, {required this.negotiated})
    : _state = negotiated ? null : RTCDataChannelState.RTCDataChannelOpen;

  final String _label;
  final int _id;
  final bool negotiated;
  final sent = <String>[];
  final sentBinary = <Uint8List>[];
  RTCDataChannelState? _state;
  bool closed = false;

  @override
  String? get label => _label;

  @override
  int? get id => _id;

  @override
  RTCDataChannelState? get state => _state;

  @override
  int? get bufferedAmount => 0;

  @override
  Future<void> send(RTCDataChannelMessage message) async => message.isBinary
      ? sentBinary.add(message.binary)
      : sent.add(message.text);

  void receive(String text) => onMessage?.call(RTCDataChannelMessage(text));

  void receiveBinary(List<int> bytes) => onMessage?.call(
    RTCDataChannelMessage.fromBinary(Uint8List.fromList(bytes)),
  );

  void opens() {
    const open = RTCDataChannelState.RTCDataChannelOpen;
    _state = open;
    onDataChannelState?.call(open);
  }

  void connecting() => _state = RTCDataChannelState.RTCDataChannelConnecting;

  @override
  Future<void> close() async {
    closed = true;
    _state = RTCDataChannelState.RTCDataChannelClosed;
  }
}

class FakePeerConnection extends RTCPeerConnection {
  FakePeerConnection(
    this.configuration, {
    this.name = 'pc',
    this.journal,
    this.transceiverGate,
  });

  final Map<String, dynamic> configuration;
  final String name;
  final List<String>? journal;
  final Completer<void>? transceiverGate;
  final rtpTransceivers = <FakeTransceiver>[];
  final remoteDescriptions = <RTCSessionDescription>[];
  final pendingRemoteMids = <String, String>{};
  final dataChannels = <FakeDataChannel>[];
  final remoteCandidates = <RTCIceCandidate>[];
  final configurations = <Map<String, dynamic>>[];
  final operations = <String>[];
  Completer<void>? configurationGate;
  var iceRestarts = 0;
  List<StatsReport> stats = [];
  Completer<void>? statsGate;
  var statsCalls = 0;
  Object? setRemoteDescriptionError;
  Object? createAnswerError;
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
  Future<void> setLocalDescription(RTCSessionDescription description) async =>
      _local = description;

  @override
  Future<RTCSessionDescription?> getLocalDescription() async => _local;

  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    if (setRemoteDescriptionError case final error?) throw error;
    remoteDescriptions.add(description);
    operations.add('remote ${description.type}');
    if (description.type != 'offer') return;
    for (final MapEntry(key: mid, value: kind) in pendingRemoteMids.entries) {
      if (rtpTransceivers.any((t) => t.mid == mid)) continue;
      rtpTransceivers.add(
        FakeTransceiver(
          mid: mid,
          sender: FakeSender('recv-sender-$mid', null),
          receiver: FakeReceiver(
            'receiver-$mid',
            FakeTrack(kind, 'r-$mid'),
            owner: this,
          ),
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
    await transceiverGate?.future;
    if (disposed) throw StateError('peerConnection is null');
    final mid = '${rtpTransceivers.length}';
    final sender = FakeSender('sender-$mid', track, owner: this)
      ..parameters = RTCRtpParameters(
        encodings: [
          for (final e in init?.sendEncodings ?? const <RTCRtpEncoding>[])
            RTCRtpEncoding(rid: e.rid),
        ],
        degradationPreference: RTCDegradationPreference.BALANCED,
      );
    final transceiver = FakeTransceiver(
      mid: mid,
      sender: sender,
      receiver: FakeReceiver('receiver-$mid', null),
      direction: init?.direction,
      sendEncodings: init?.sendEncodings,
    );
    rtpTransceivers.add(transceiver);
    return transceiver;
  }

  @override
  Future<List<StatsReport>> getStats([MediaStreamTrack? track]) async {
    statsCalls++;
    await statsGate?.future;
    return stats;
  }

  @override
  Future<RTCDataChannel> createDataChannel(
    String label,
    RTCDataChannelInit dataChannelDict,
  ) async {
    final channel = FakeDataChannel(
      label,
      dataChannelDict.id,
      negotiated: dataChannelDict.negotiated,
    );
    dataChannels.add(channel);
    return channel;
  }

  FakeDataChannel? dataChannel(String label) =>
      dataChannels.where((c) => c.label == label && !c.closed).lastOrNull;

  @override
  Future<void> addCandidate(RTCIceCandidate candidate) async {
    if (remoteDescriptions.isEmpty) {
      throw StateError('no remote description for a candidate');
    }
    remoteCandidates.add(candidate);
  }

  @override
  Future<void> setConfiguration(Map<String, dynamic> configuration) async {
    await configurationGate?.future;
    configurations.add(configuration);
    operations.add('configuration');
  }

  @override
  Future<void> restartIce() async => iceRestarts++;

  void emitDataChannel(FakeDataChannel channel) => onDataChannel?.call(channel);

  void changeState(RTCPeerConnectionState state) =>
      onConnectionState?.call(state);

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
  FakeKeyProvider({this.journal, this.refuseKey = false});

  final List<String>? journal;
  bool refuseKey;
  final slots = <int, Uint8List>{};
  bool disposed = false;

  @override
  String get id => 'fake-key-provider';

  @override
  Future<void> setSharedKey({required Uint8List key, int index = 0}) async {
    if (refuseKey) throw StateError('key provider refused the key');
    slots[index] = key;
  }

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
    this.keyProvider,
    this.failKeyIndex = false,
    this.journal,
  });

  @override
  final String participantId;
  final bool failEnable;
  final RTCRtpSender? sender;
  final KeyProvider? keyProvider;
  final bool failKeyIndex;
  final List<String>? journal;
  bool isEnabled = false;
  bool disposed = false;
  int currentKeyIndex = 0;
  int? keyIndexAtEnable;

  @override
  Future<bool> setKeyIndex(int index) async {
    if (failKeyIndex) throw StateError('frame cryptor refused its key slot');
    currentKeyIndex = index;
    return true;
  }

  @override
  Future<bool> setEnabled(bool enabled) async {
    if (failEnable) throw StateError('frame cryptor refused to start');
    isEnabled = enabled;
    if (enabled) keyIndexAtEnable ??= currentKeyIndex;
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
  final providerOptions = <KeyProviderOptions>[];
  bool refuseKey = false;
  final cryptors = <FakeFrameCryptor>[];
  final failEnableFor = <String>{};
  final failKeyIndexFor = <String>{};
  Completer<void>? senderGate;
  Completer<void>? receiverGate;

  Iterable<FakeFrameCryptor> get live => cryptors.where((c) => !c.disposed);

  Set<String> get liveLabels => {for (final c in live) c.participantId};

  @override
  Future<KeyProvider> createDefaultKeyProvider(
    KeyProviderOptions options,
  ) async {
    final provider = FakeKeyProvider(journal: journal, refuseKey: refuseKey);
    providerOptions.add(options);
    keyProviders.add(provider);
    return provider;
  }

  FakeFrameCryptor _cryptor(
    String label, {
    RTCRtpSender? sender,
    required KeyProvider keyProvider,
  }) {
    final cryptor = FakeFrameCryptor(
      label,
      failEnable: failEnableFor.contains(label),
      failKeyIndex: failKeyIndexFor.contains(label),
      sender: sender,
      keyProvider: keyProvider,
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
    if (sender is FakeSender && sender.closed) {
      throw StateError('peerConnection not found');
    }
    return _cryptor(participantId, sender: sender, keyProvider: keyProvider);
  }

  @override
  Future<FrameCryptor> createFrameCryptorForRtpReceiver({
    required String participantId,
    required RTCRtpReceiver receiver,
    required Algorithm algorithm,
    required KeyProvider keyProvider,
  }) async {
    await receiverGate?.future;
    if (receiver is FakeReceiver && (receiver.owner?.disposed ?? false)) {
      throw StateError('peerConnection not found');
    }
    return _cryptor(participantId, keyProvider: keyProvider);
  }
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
  Completer<void>? adoptGate;
  Completer<void>? captureGate;
  Completer<void>? transceiverGate;
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
      transceiverGate: transceiverGate,
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
    if (label.startsWith('adopted_')) await adoptGate?.future;
    if (adoptErrors[label] case final error?) throw error;
    final stream = FakeMediaStream(label);
    streams.add(stream);
    return stream;
  }

  @override
  FrameCryptorFactory get frameCryptorFactory => cryptors;

  @override
  Future<bool> switchCamera(MediaStreamTrack track) async {
    cameraSwitches++;
    return false;
  }
}

StatsReport candidatePair(
  String id, {
  double rttSeconds = 0.04,
  bool nominated = true,
  bool succeeded = true,
  double? uploadBps,
}) => StatsReport(id, 'candidate-pair', 0, {
  'state': succeeded ? 'succeeded' : 'in-progress',
  'nominated': nominated,
  'currentRoundTripTime': rttSeconds,
  'availableOutgoingBitrate': ?uploadBps,
});

StatsReport outboundRtp(String id, {String kind = 'audio', int? packetsSent}) =>
    StatsReport(id, 'outbound-rtp', 0, {
      'kind': kind,
      'packetsSent': ?packetsSent,
    });

StatsReport remoteInboundRtp(String localId, double fractionLost) =>
    StatsReport('remote-$localId', 'remote-inbound-rtp', 0, {
      'localId': localId,
      'fractionLost': fractionLost,
    });

StatsReport inboundRtp(String id, {required int lost, required int received}) =>
    StatsReport(id, 'inbound-rtp', 0, {
      'packetsLost': lost,
      'packetsReceived': received,
    });
