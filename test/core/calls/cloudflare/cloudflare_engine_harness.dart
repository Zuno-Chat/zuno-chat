import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:zuno/core/calls/cloudflare/cloudflare_connection.dart';
import 'package:zuno/core/calls/cloudflare/placeholder_video.dart';
import 'package:zuno/core/calls/media/call_connection.dart';
import 'package:zuno/core/calls/media/call_media_engine.dart';
import 'package:zuno/core/calls/media/webrtc_backend.dart';
import 'package:zuno/core/calls/models/call_engine_participant.dart';
import 'package:zuno/core/calls/models/call_engine_status.dart';
import 'package:zuno/core/calls/models/call_kind.dart';
import 'package:zuno/core/calls/models/voip_participant_id.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../../helpers/call_fixtures.dart';
import '../../../helpers/fake_http.dart';
import '../../../helpers/fake_webrtc.dart';
import '../../../helpers/hybrid_fake_async.dart';

class SfuRequest {
  SfuRequest(this.method, this.path, this.body);

  final String method;
  final String path;
  final Map<String, dynamic>? body;

  List<Map<String, dynamic>> get tracks =>
      (body?['tracks'] as List? ?? const []).cast<Map<String, dynamic>>();

  Map<String, dynamic>? get sessionDescription =>
      body?['sessionDescription'] as Map<String, dynamic>?;

  List<Map<String, dynamic>> get dataChannels =>
      (body?['dataChannels'] as List? ?? const []).cast<Map<String, dynamic>>();

  String get session => path.split('/')[2];
}

class FakeSfu {
  FakeSfu(this.backend);

  final FakeWebRtcBackend backend;
  final requests = <SfuRequest>[];
  final pulledTracks = <Map<String, dynamic>>[];
  final missingTracks = <String>{};
  String missingTrackCode = 'not_found_track_error';
  int? sessionStatus;
  Map<String, Object?>? sessionRefusal;
  int? renegotiateStatus;
  int lostPullResponses = 0;
  int refusedPushes = 0;
  bool connectOnPush = false;
  bool reuseMids = false;
  bool removedFromCall = false;
  bool refuseDataChannels = false;
  final refusedChannelSessions = <String>{};
  String? answerSdp;
  String? offerSdp;
  Completer<void>? sessionGate;
  Completer<void>? pullGate;
  Completer<void>? closeGate;
  Completer<void>? channelGate;
  var _sessions = 0;
  var _answers = 0;
  var _offers = 0;
  var _nextMid = 100;
  var _nextChannelId = 1;
  var _channelOffers = 0;
  final _midByTrack = <String, String>{};
  final _awaitingAnswer = <String>{};

  late final http.Client client = FakeHttpClient(_handle);

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
  List<SfuRequest> get establishes =>
      _where('POST', '/datachannels/establish').toList();
  List<SfuRequest> get channelOpens =>
      _where('POST', '/datachannels/new').toList();
  List<SfuRequest> get channelCloses =>
      _where('PUT', '/datachannels/close').toList();

  static http.Response _json(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status);

  Future<http.Response> _handle(http.Request request) async {
    final path = request.url.path.split('/cloudflare').last;
    final body = request.body.isEmpty
        ? null
        : jsonDecode(request.body) as Map<String, dynamic>;
    final recorded = SfuRequest(request.method, path, body);
    requests.add(recorded);

    if (removedFromCall) {
      return _json({
        'errcode': 'IM.ZUNO.CALL_REMOVED',
        'error': 'Removed from this call',
      }, 403);
    }
    if (path == '/sessions/new') {
      await sessionGate?.future;
      if (sessionStatus case final status?) {
        return _json(sessionRefusal ?? {'errorCode': 'refused'}, status);
      }
      return _json({'sessionId': 's${++_sessions}'});
    }
    final session = recorded.session;
    if (!path.endsWith('/renegotiate') && _awaitingAnswer.contains(session)) {
      return _json({'errorCode': 'invalid_session_description'}, 406);
    }
    if (path.endsWith('/tracks/new')) {
      if (recorded.sessionDescription != null) {
        if (refusedPushes > 0) {
          refusedPushes--;
          return _json({'errorCode': 'refused'}, 500);
        }
        if (connectOnPush) {
          backend.pc.onConnectionState?.call(
            RTCPeerConnectionState.RTCPeerConnectionStateConnected,
          );
        }
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
      _awaitingAnswer.add(session);
      if (lostPullResponses > 0) {
        lostPullResponses--;
        throw const SocketException('Connection reset by peer');
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
                'errorCode': missingTrackCode,
                'errorDescription': 'Track not found',
              },
        ],
      });
    }
    if (path.endsWith('/renegotiate')) {
      if (renegotiateStatus case final status?) {
        return _json({'errorCode': 'refused'}, status);
      }
      _awaitingAnswer.remove(session);
      return _json({});
    }
    if (path.contains('/datachannels/')) {
      if (refuseDataChannels) {
        return _json({
          'errcode': 'M_UNRECOGNIZED',
          'error': 'Unrecognized',
        }, 404);
      }
      if (path.endsWith('/datachannels/establish')) {
        _awaitingAnswer.add(session);
        return _json({
          'requiresImmediateRenegotiation': true,
          'dataChannel': {'dataChannelName': 'server-events', 'id': 0},
          'sessionDescription': {
            'type': 'offer',
            'sdp': 'sfu datachannel offer ${++_channelOffers}',
          },
        });
      }
      if (path.endsWith('/datachannels/new')) {
        await channelGate?.future;
        return _json({
          'dataChannels': [
            for (final channel in recorded.dataChannels)
              refusedChannelSessions.contains(channel['sessionId'])
                  ? {...channel, 'errorCode': 'IM.ZUNO.TRACK_NOT_IN_CALL'}
                  : {...channel, 'id': _nextChannelId++},
          ],
        });
      }
      return _json({'dataChannels': []});
    }
    if (path.endsWith('/tracks/close')) {
      await closeGate?.future;
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

final cloudflareBaseUri = Uri.parse(
  'https://example.org/_synapse/client/zuno/calls/cloudflare',
);

class FakePlaceholderVideoSource implements PlaceholderVideoSource {
  bool available = true;
  Object? error;
  final created = <PlaceholderVideo>[];
  final released = <PlaceholderVideo>[];

  @override
  Future<PlaceholderVideo?> create() async {
    if (error case final error?) throw error;
    if (!available) return null;
    final placeholder = (
      stream: FakeMediaStream('placeholder-${created.length + 1}'),
      track: FakeTrack('video', 'black-${created.length + 1}'),
    );
    created.add(placeholder);
    return placeholder;
  }

  @override
  Future<void> release(PlaceholderVideo placeholder) async {
    released.add(placeholder);
  }
}

class CloudflareTestConnections implements CallConnectionOpener {
  CloudflareTestConnections({
    Uri Function()? baseUri,
    this.iceServers,
    this.httpClient,
    this.placeholders = const PlaceholderVideoSource(),
  }) : baseUri = baseUri ?? (() => cloudflareBaseUri);

  final Uri Function() baseUri;
  final Future<List<Map<String, Object?>>>? iceServers;
  final http.Client? httpClient;
  final PlaceholderVideoSource placeholders;
  late final CloudflareConnection connection;

  @override
  Future<CallConnection> open(
    CallSpec spec,
    CallConnectionHost host, {
    bool rediscover = false,
  }) async => connection = CloudflareConnection(
    baseUri: baseUri,
    authorization: () async => 'Bearer test-token',
    spec: spec,
    host: host,
    iceServers: iceServers,
    httpClient: httpClient,
    placeholders: placeholders,
  );
}

({CallMediaEngine engine, CloudflareConnection connection})
buildCloudflareEngine({
  CallKind kind = CallKind.voice,
  bool lowDataMode = false,
  Uri Function()? baseUri,
  Future<List<Map<String, Object?>>>? iceServers,
  http.Client? httpClient,
  WebRtcBackend webRtc = const WebRtcBackend(),
  PlaceholderVideoSource placeholders = const PlaceholderVideoSource(),
  PlatformCapabilities? capabilities,
}) {
  final connections = CloudflareTestConnections(
    baseUri: baseUri,
    iceServers: iceServers,
    httpClient: httpClient,
    placeholders: placeholders,
  );
  final engine = CallMediaEngine(
    connections: connections,
    spec: (roomId: '!room:example.org', callId: 'call1'),
    kind: kind,
    lowDataMode: lowDataMode,
    webRtc: webRtc,
    capabilities: capabilities,
  );
  return (engine: engine, connection: connections.connection);
}

class EngineHarness {
  EngineHarness(
    this.async, {
    CallKind kind = CallKind.voice,
    bool lowDataMode = false,
    PlatformCapabilities? capabilities,
    Uri Function()? baseUri,
  }) {
    final built = buildCloudflareEngine(
      kind: kind,
      lowDataMode: lowDataMode,
      baseUri: baseUri,
      iceServers: Future.value(iceServers),
      httpClient: sfu.client,
      webRtc: backend,
      placeholders: placeholders,
      capabilities: capabilities,
    );
    engine = built.engine;
    connection = built.connection;
    engine.statusStream.listen(statuses.add);
    engine.participantsStream.listen(emitted.add);
    engine.localStateChangedStream.listen((_) => localStateChanges++);
  }

  final FakeAsync async;
  final backend = FakeWebRtcBackend();
  final placeholders = FakePlaceholderVideoSource();
  late final sfu = FakeSfu(backend);
  late final CallMediaEngine engine;
  late final CloudflareConnection connection;
  final statuses = <CallEngineStatus>[];
  final emitted = <List<CallEngineParticipant>>[];
  var localStateChanges = 0;

  static const iceServers = [
    {'urls': 'turn:turn.example.org', 'username': 'u', 'credential': 'c'},
  ];

  T wait<T>(Future<T> future) => async.waitFor(future);

  void flush() => async.flushAll();

  void join() => wait(engine.join());

  void encrypt() => wait(keyEveryone(engine));

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
    bool advertisesQuality = false,
    String membershipEventId = r'$membership',
  }) {
    engine.updateRemoteParticipant(id, {
      'sessionId': sessionId,
      'tracks': {'audio': 'audio', if (video) 'video': 'video'},
      'audioMuted': audioMuted,
      'videoEnabled': videoEnabled,
      'encrypted': encrypted,
      if (advertisesQuality) 'dataChannels': {'quality': 'quality'},
    }, membershipEventId: membershipEventId);
    flush();
  }

  void leave() => wait(engine.leave());

  static StatsReport outbound(String kind) => StatsReport(
    'out-$kind',
    'outbound-rtp',
    0,
    {'kind': kind, 'bytesSent': 1200},
  );

  void mediaFlows({Set<String> kinds = const {'audio', 'video'}}) {
    pc.stats = [for (final kind in kinds) outbound(kind)];
    async.elapse(const Duration(seconds: 2));
    flush();
  }

  void pollStats(Iterable<List<StatsReport>> polls) {
    for (final stats in polls) {
      pc.stats = stats;
      async.elapse(const Duration(seconds: 3));
      flush();
    }
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

void runEngineCall(
  void Function(EngineHarness call) body, {
  required CallKind kind,
  bool lowDataMode = false,
  PlatformCapabilities? capabilities,
}) {
  fakeAsync((async) {
    final call = EngineHarness(
      async,
      kind: kind,
      lowDataMode: lowDataMode,
      capabilities: capabilities,
    );
    body(call);
    call.leave();
    call.flush();
  });
}
