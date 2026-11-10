import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' show Client;
import 'package:zuno/core/calls/livekit/livekit_connection.dart';
import 'package:zuno/core/calls/livekit/livekit_signal_client.dart';
import 'package:zuno/core/calls/livekit/proto/livekit_models.pb.dart';
import 'package:zuno/core/calls/livekit/proto/livekit_rtc.pb.dart';
import 'package:zuno/core/calls/media/call_connection.dart';
import 'package:zuno/core/calls/media/call_media_engine.dart';
import 'package:zuno/core/calls/models/call_engine_participant.dart';
import 'package:zuno/core/calls/models/call_engine_status.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/models/voip_participant_id.dart';

import '../../../helpers/call_fixtures.dart';
import '../../../helpers/fake_http.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/fake_webrtc.dart';
import '../../../helpers/hybrid_fake_async.dart';
import 'fake_livekit_socket.dart';

TrackInfo remoteTrack(
  String sid, {
  TrackType type = TrackType.AUDIO,
  Encryption_Type encryption = Encryption_Type.GCM,
}) => TrackInfo(
  sid: sid,
  type: type,
  source: type == TrackType.VIDEO ? TrackSource.CAMERA : TrackSource.MICROPHONE,
  encryption: encryption,
);

ParticipantInfo remoteParticipant(
  String sid,
  String identity, {
  List<TrackInfo> tracks = const [],
  int version = 1,
}) => ParticipantInfo(
  sid: sid,
  identity: identity,
  state: ParticipantInfo_State.ACTIVE,
  tracks: tracks,
  version: version,
);

class ScriptedSocket extends FakeLiveKitSocket {
  ScriptedSocket(this._server, this.url);

  final ScriptedLiveKitServer _server;
  final Uri url;
  bool _ended = false;

  bool get resuming => url.queryParameters['reconnect'] == '1';

  @override
  void send(List<int> bytes) {
    super.send(bytes);
    _server._handle(this, sent.last);
  }

  @override
  void serverSends(SignalResponse response) {
    if (closed || _ended) return;
    super.serverSends(response);
  }

  @override
  Future<void> serverCloses() {
    _ended = true;
    unawaited(super.serverCloses());
    return Future.value();
  }
}

class ScriptedLiveKitServer extends LiveKitTestServer<ScriptedSocket> {
  String identity = 'lk-me';
  String participantSid = 'PA_me';
  bool forceRelay = false;
  List<ICEServer> iceServers = [
    ICEServer(
      urls: ['turn:lk.example.org:443?transport=tcp'],
      username: 'u',
      credential: 'c',
    ),
  ];
  List<ICEServer> resumeIceServers = [
    ICEServer(urls: ['turn:lk2.example.org:443'], username: 'u2'),
  ];
  final others = <ParticipantInfo>[];
  SignalResponse? resumeRefusal;
  bool resumeForceRelay = false;
  bool offersSubscriberWithJoin = false;
  bool offersSubscriberWithResume = false;
  bool holdTrackPublished = false;
  final _heldPublished = <void Function()>[];
  bool holdAnswers = false;
  final _heldAnswers = <void Function()>[];
  String? answerSdp;
  List<AudioTrackFeature> _audioFeatures = const [];
  var _answers = 0;
  var _offers = 0;

  Iterable<SignalRequest> sentOf(SignalRequest_Message kind) =>
      socket.sentOf(kind);

  List<AddTrackRequest> get addTracks => [
    for (final request in sentOf(SignalRequest_Message.addTrack))
      request.addTrack,
  ];

  List<UpdateSubscription> get subscriptions => [
    for (final request in sentOf(SignalRequest_Message.subscription))
      request.subscription,
  ];

  @override
  ScriptedSocket newSocket(Uri url) => ScriptedSocket(this, url);

  @override
  void opened(ScriptedSocket socket) {
    scheduleMicrotask(() {
      socket.serverSends(
        socket.resuming
            ? resumeRefusal ??
                  SignalResponse(
                    reconnect: ReconnectResponse(
                      iceServers: resumeIceServers,
                      clientConfiguration: resumeForceRelay
                          ? ClientConfiguration(
                              forceRelay: ClientConfigSetting.ENABLED,
                            )
                          : null,
                    ),
                  )
            : SignalResponse(join: _join()),
      );
      if (socket.resuming
          ? offersSubscriberWithResume && resumeRefusal == null
          : offersSubscriberWithJoin) {
        socket.serverSends(
          SignalResponse(
            offer: SessionDescription(
              type: 'offer',
              sdp: 'lk subscriber offer ${++_offers}',
              id: 3,
            ),
          ),
        );
      }
    });
  }

  JoinResponse _join() => JoinResponse(
    participant: ParticipantInfo(sid: participantSid, identity: identity),
    otherParticipants: others,
    iceServers: iceServers,
    clientConfiguration: forceRelay
        ? ClientConfiguration(forceRelay: ClientConfigSetting.ENABLED)
        : null,
    subscriberPrimary: true,
    pingInterval: 5,
    pingTimeout: 15,
  );

  void _handle(ScriptedSocket socket, SignalRequest request) {
    switch (request.whichMessage()) {
      case SignalRequest_Message.addTrack:
        final add = request.addTrack;
        if (add.type == TrackType.AUDIO) _audioFeatures = add.audioFeatures;
        void publish() => socket.serverSends(
          SignalResponse(
            trackPublished: TrackPublishedResponse(
              cid: add.cid,
              track: TrackInfo(
                sid: 'TR_${add.cid}',
                type: add.type,
                source: add.source,
                encryption: add.encryption,
              ),
            ),
          ),
        );
        holdTrackPublished
            ? _heldPublished.add(publish)
            : scheduleMicrotask(publish);
      case SignalRequest_Message.offer:
        final sdp = _withServerOpusParams(
          answerSdp ?? 'lk answer ${++_answers}',
        );
        void answer() => socket.serverSends(
          SignalResponse(
            answer: SessionDescription(type: 'answer', sdp: sdp),
          ),
        );
        holdAnswers ? _heldAnswers.add(answer) : scheduleMicrotask(answer);
      case SignalRequest_Message.pingReq:
        scheduleMicrotask(
          () => socket.serverSends(
            SignalResponse(
              pongResp: Pong(lastPingTimestamp: request.pingReq.timestamp),
            ),
          ),
        );
      default:
    }
  }

  String _withServerOpusParams(String sdp) {
    final opus = RegExp(
      r'^a=rtpmap:(\d+) opus/',
      multiLine: true,
    ).firstMatch(sdp)?.group(1);
    if (opus == null) return sdp;
    final dtx = !_audioFeatures.contains(AudioTrackFeature.TF_NO_DTX);
    return [
      for (final line in sdp.split('\r\n'))
        if (line.startsWith('a=fmtp:$opus ')) ...[
          ?_serverOpusFmtp(opus, line.substring('a=fmtp:$opus '.length), dtx),
        ] else
          line,
    ].join('\r\n');
  }

  static String? _serverOpusFmtp(String payload, String params, bool dtx) {
    final kept = [
      for (final param in params.split(';'))
        if (!{'', 'usedtx', 'stereo'}.contains(param.split('=').first.trim()))
          param,
      if (dtx) 'usedtx=1',
    ];
    return kept.isEmpty ? null : 'a=fmtp:$payload ${kept.join(';')}';
  }

  void releaseTrackPublished() {
    holdTrackPublished = false;
    for (final publish in List.of(_heldPublished)) {
      publish();
    }
    _heldPublished.clear();
  }

  void releaseAnswers() {
    holdAnswers = false;
    for (final answer in List.of(_heldAnswers)) {
      answer();
    }
    _heldAnswers.clear();
  }

  void sends(SignalResponse response) => socket.serverSends(response);

  void participantUpdate(List<ParticipantInfo> participants) => sends(
    SignalResponse(update: ParticipantUpdate(participants: participants)),
  );

  void offersSubscriber({int id = 1}) => sends(
    SignalResponse(
      offer: SessionDescription(
        type: 'offer',
        sdp: 'lk subscriber offer ${++_offers}',
        id: id,
      ),
    ),
  );

  void trickles(String candidate, SignalTarget target) => sends(
    SignalResponse(
      trickle: TrickleRequest(
        candidateInit: jsonEncode({
          'candidate': candidate,
          'sdpMid': '0',
          'sdpMLineIndex': 0,
        }),
        target: target,
      ),
    ),
  );

  void leaves(
    LeaveRequest_Action action, {
    DisconnectReason reason = DisconnectReason.UNKNOWN_REASON,
  }) => sends(
    SignalResponse(
      leave: LeaveRequest(action: action, reason: reason),
    ),
  );
}

class FakeLiveKitModule {
  final requests = <http.Request>[];
  final answers = <Object>[];
  Completer<void>? gate;
  var _tokens = 0;

  static http.Response refusal(Map<String, Object?> body, int status) =>
      http.Response(jsonEncode(body), status);

  late final http.Client client = FakeHttpClient((request) async {
    requests.add(request);
    await gate?.future;
    if (answers.isNotEmpty) {
      final answer = answers.removeAt(0);
      if (answer is http.Response) return answer;
      throw answer;
    }
    return http.Response(
      jsonEncode({
        'url': 'wss://lk.example.org',
        'token': 'lk-token-${++_tokens}',
      }),
      200,
    );
  });
}

class LiveKitTestConnections implements CallConnectionOpener {
  LiveKitTestConnections({
    required this.client,
    required this.httpClient,
    required this.connect,
  });

  final Client client;
  final http.Client httpClient;
  final LiveKitSocketConnect connect;
  late final LiveKitConnection connection;

  @override
  Future<CallConnection> open(
    CallSpec spec,
    CallConnectionHost host, {
    bool rediscover = false,
  }) async => connection = LiveKitConnection(
    client: client,
    spec: spec,
    host: host,
    httpClient: httpClient,
    connect: connect,
  );
}

class LiveKitCall {
  LiveKitCall(this.async, {CallKind kind = CallKind.voice}) {
    final client = buildTestClient()
      ..homeserver = Uri.parse('https://example.org')
      ..accessToken = 'syt_token';
    connections = LiveKitTestConnections(
      client: client,
      httpClient: module.client,
      connect: server.connect,
    );
    engine = CallMediaEngine(
      connections: connections,
      spec: (roomId: '!room:example.org', callId: 'call1'),
      kind: kind,
      webRtc: backend,
    );
    engine.statusStream.listen(statuses.add);
    engine.participantsStream.listen(emitted.add);
    flush();
  }

  final FakeAsync async;
  final backend = FakeWebRtcBackend();
  final server = ScriptedLiveKitServer();
  final module = FakeLiveKitModule();
  late final LiveKitTestConnections connections;
  late final CallMediaEngine engine;
  final statuses = <CallEngineStatus>[];
  final emitted = <List<CallEngineParticipant>>[];
  Future<void>? joining;

  LiveKitConnection get connection => connections.connection;

  T wait<T>(Future<T> future) => async.waitFor(future);

  void flush() => async.flushAll();

  void elapse(Duration duration) {
    async.elapse(duration);
    flush();
  }

  void join() => wait(engine.join());

  void startJoin() {
    joining = engine.join();
    flush();
  }

  void encrypt() => wait(keyEveryone(engine));

  void leave() => wait(engine.leave());

  List<FakePeerConnection> get _pcs => backend.peerConnections;

  FakePeerConnection get publisher => _pcs[_pcs.length - 2];

  FakePeerConnection get subscriber => _pcs.last;

  void connectPeers() {
    publisher.changeState(
      RTCPeerConnectionState.RTCPeerConnectionStateConnected,
    );
    subscriber.changeState(
      RTCPeerConnectionState.RTCPeerConnectionStateConnected,
    );
    flush();
  }

  void remoteJoins({
    VoipParticipantId id = ann,
    String identity = 'lk-ann',
    bool videoEnabled = true,
    bool encrypted = true,
  }) {
    engine.updateRemoteParticipant(id, {
      'identity': identity,
      'audioMuted': false,
      'videoEnabled': videoEnabled,
      'encrypted': encrypted,
    }, membershipEventId: r'$membership');
    flush();
  }

  var _mids = 0;

  void remoteTrackArrives({
    required String participantSid,
    required String trackSid,
    String kind = 'audio',
  }) {
    final mid = 'sub-${_mids++}';
    subscriber.pendingRemoteMids[mid] = kind;
    server.offersSubscriber();
    flush();
    subscriber.emitTrack(mid, FakeMediaStream('$participantSid|$trackSid'));
    flush();
  }

  CallEngineParticipant get local =>
      engine.participants.firstWhere((p) => p.isLocal);

  CallEngineParticipant? remote([VoipParticipantId id = ann]) =>
      engine.participants.where((p) => p.id == id).firstOrNull;

  MediaStreamTrack get microphone => local.audioStream!.getAudioTracks().single;

  MediaStreamTrack get camera => local.videoStream!.getVideoTracks().single;

  FakeSender senderOf(MediaStreamTrack track) => publisher.rtpTransceivers
      .firstWhere((t) => t.sender.track?.id == track.id)
      .sender;
}

void runLiveKitCall(
  void Function(LiveKitCall call) body, {
  CallKind kind = CallKind.voice,
}) {
  fakeAsync((async) {
    final call = LiveKitCall(async, kind: kind);
    body(call);
    call.leave();
    call.flush();
    expect(async.periodicTimerCount, 0);
  });
}
