import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:zuno/core/calls/cloudflare/cloudflare_call_engine.dart';
import 'package:zuno/core/calls/models/call_engine_participant.dart';
import 'package:zuno/core/calls/models/call_engine_status.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/models/voip_participant_id.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../../helpers/fake_webrtc.dart';

class SfuRequest {
  SfuRequest(this.method, this.path, this.body);

  final String method;
  final String path;
  final Map<String, dynamic>? body;

  List<Map<String, dynamic>> get tracks =>
      (body?['tracks'] as List? ?? const []).cast<Map<String, dynamic>>();

  Map<String, dynamic>? get sessionDescription =>
      body?['sessionDescription'] as Map<String, dynamic>?;
}

class FakeSfu {
  FakeSfu(this.backend);

  final FakeWebRtcBackend backend;
  final requests = <SfuRequest>[];
  final pulledTracks = <Map<String, dynamic>>[];
  final missingTracks = <String>{};
  int? sessionStatus;
  int? renegotiateStatus;
  bool reuseMids = false;
  bool closeRenegotiates = false;
  String? answerSdp;
  String? offerSdp;
  Completer<void>? sessionGate;
  Completer<void>? pullGate;
  var _sessions = 0;
  var _answers = 0;
  var _offers = 0;
  var _nextMid = 100;
  final _midByTrack = <String, String>{};

  late final http.Client client = MockClient(_handle);

  Iterable<SfuRequest> _where(String method, String suffix) =>
      requests.where((r) => r.method == method && r.path.endsWith(suffix));

  List<SfuRequest> get pushes => [
    for (final r in _where('POST', '/tracks/new'))
      if (r.sessionDescription != null) r,
  ];
  List<SfuRequest> get pulls => [
    for (final r in _where('POST', '/tracks/new'))
      if (r.sessionDescription == null) r,
  ];
  List<SfuRequest> get renegotiations => _where('PUT', '/renegotiate').toList();
  List<SfuRequest> get closes => _where('PUT', '/tracks/close').toList();

  static http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);

  Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path.split('/cloudflare').last;
    final body = request.body.isEmpty
        ? null
        : jsonDecode(request.body) as Map<String, dynamic>;
    final recorded = SfuRequest(request.method, path, body);
    requests.add(recorded);

    if (path == '/sessions/new') {
      await sessionGate?.future;
      if (sessionStatus case final status?) {
        return _json({'errorCode': 'refused'}, status);
      }
      return _json({'sessionId': 's${++_sessions}'});
    }
    if (path.endsWith('/tracks/new')) {
      if (recorded.sessionDescription != null) {
        return _json({
          'requiresImmediateRenegotiation': false,
          'sessionDescription': {
            'type': 'answer',
            'sdp': answerSdp ?? 'sfu answer ${++_answers}',
          },
          'tracks': recorded.tracks,
        });
      }
      await pullGate?.future;
      final pulled = [
        for (final track in recorded.tracks)
          if (!missingTracks.contains(track['trackName']))
            {
              ...track,
              'mid': _midFor('${track['sessionId']}/${track['trackName']}'),
            },
      ];
      pulledTracks.addAll(pulled);
      for (final track in pulled) {
        backend.pc.pendingRemoteMids[track['mid'] as String] =
            track['trackName'] as String;
      }
      return _json({
        'requiresImmediateRenegotiation': true,
        'sessionDescription': {
          'type': 'offer',
          'sdp': offerSdp ?? 'sfu offer ${++_offers}',
        },
        'tracks': [
          ...pulled,
          for (final track in recorded.tracks)
            if (missingTracks.contains(track['trackName']))
              {
                ...track,
                'errorCode': 'not_found_track_error',
                'errorDescription': 'Track not found',
              },
        ],
      });
    }
    if (path.endsWith('/renegotiate')) {
      if (renegotiateStatus case final status?) {
        return _json({'errorCode': 'refused'}, status);
      }
      return _json({});
    }
    if (path.endsWith('/tracks/close')) {
      if (closeRenegotiates) {
        return _json({
          'requiresImmediateRenegotiation': true,
          'sessionDescription': {'type': 'offer', 'sdp': 'sfu close offer'},
          'tracks': [],
        });
      }
      return _json({'requiresImmediateRenegotiation': false, 'tracks': []});
    }
    return _json({'errorCode': 'unknown path $path'}, 404);
  }

  String _midFor(String key) {
    if (!reuseMids) return '${_nextMid++}';
    final trackName = key.split('/').last;
    return _midByTrack[trackName] ??= '${_nextMid++}';
  }
}

const ann = VoipParticipantId(userId: '@ann:example.org', deviceId: 'ANN');

String receiverLabel(VoipParticipantId id, String trackName) =>
    '$id-$trackName';

String opusSdp(String fmtp) => [
  'v=0',
  'o=- 1 2 IN IP4 127.0.0.1',
  's=-',
  't=0 0',
  'm=audio 9 UDP/TLS/RTP/SAVPF 111',
  'a=mid:0',
  'a=rtpmap:111 opus/48000/2',
  'a=fmtp:111 $fmtp',
  '',
].join('\r\n');

Uint8List callKey() => Uint8List.fromList(List<int>.generate(32, (i) => i));

class EngineHarness {
  EngineHarness(
    this.async, {
    CallKind kind = CallKind.voice,
    bool lowDataMode = false,
    PlatformCapabilities? capabilities,
  }) {
    engine = CloudflareCallEngine(
      baseUri: Uri.parse(
        'https://example.org/_synapse/client/zuno/calls/cloudflare',
      ),
      authorization: () async => 'Bearer test-token',
      kind: kind,
      lowDataMode: lowDataMode,
      iceServers: Future.value(iceServers),
      httpClient: sfu.client,
      webRtc: backend,
      capabilities: capabilities,
    );
    engine.statusStream.listen(statuses.add);
    engine.participantsStream.listen(emitted.add);
    engine.localStateChangedStream.listen((_) => localStateChanges++);
  }

  final FakeAsync async;
  final backend = FakeWebRtcBackend();
  late final sfu = FakeSfu(backend);
  late final CloudflareCallEngine engine;
  final statuses = <CallEngineStatus>[];
  final emitted = <List<CallEngineParticipant>>[];
  var localStateChanges = 0;

  static const iceServers = [
    {'urls': 'turn:turn.example.org', 'username': 'u', 'credential': 'c'},
  ];

  T wait<T>(Future<T> future) {
    late T value;
    Object? error;
    var done = false;
    future.then(
      (v) {
        value = v;
        done = true;
      },
      onError: (Object e) {
        error = e;
        done = true;
      },
    );
    for (var i = 0; i < 10 && !done; i++) {
      async.flushMicrotasks();
      async.elapse(Duration.zero);
    }
    if (error case final e?) throw e;
    expect(done, isTrue, reason: 'the future never completed');
    return value;
  }

  void flush() {
    for (var i = 0; i < 10; i++) {
      async.flushMicrotasks();
      async.elapse(Duration.zero);
    }
  }

  void join() => wait(engine.join());

  void encrypt() => wait(engine.setEncryptionKey(callKey()));

  void joinEncrypted() {
    join();
    encrypt();
  }

  void remoteJoins({
    VoipParticipantId id = ann,
    String sessionId = 'remote-1',
    bool video = true,
    bool videoEnabled = true,
    bool encrypted = true,
    bool audioMuted = false,
    bool lowBandwidth = false,
  }) {
    engine.updateRemoteParticipant(id, {
      'sessionId': sessionId,
      'tracks': {'audio': 'audio', if (video) 'video': 'video'},
      'audioMuted': audioMuted,
      'videoEnabled': videoEnabled,
      'encrypted': encrypted,
      'lowBandwidth': lowBandwidth,
    });
    flush();
  }

  void leave() => wait(engine.leave());

  static StatsReport outbound(String kind, int bytesSent) => StatsReport(
    'out-$kind',
    'outbound-rtp',
    0,
    {'kind': kind, 'bytesSent': bytesSent},
  );

  void mediaFlows({Set<String> kinds = const {'audio', 'video'}}) {
    pc.stats = [for (final kind in kinds) outbound(kind, 1200)];
    async.elapse(const Duration(seconds: 2));
    flush();
  }

  FakePeerConnection get pc => backend.pc;

  CallEngineParticipant get local =>
      engine.participants.firstWhere((p) => p.isLocal);

  CallEngineParticipant? remote([VoipParticipantId id = ann]) =>
      engine.participants.where((p) => p.id == id).firstOrNull;

  MediaStreamTrack get microphone => local.audioStream!.getAudioTracks().single;

  MediaStreamTrack get camera => local.videoStream!.getVideoTracks().single;

  FakeTransceiver get videoSlot => pc.rtpTransceivers[1];

  List<String> pulledMids(String trackName) => [
    for (final t in sfu.pulledTracks)
      if (t['trackName'] == trackName) t['mid'] as String,
  ];
}
