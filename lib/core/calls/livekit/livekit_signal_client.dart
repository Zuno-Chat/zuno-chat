import 'dart:async';

import 'package:clock/clock.dart';
import 'package:fixnum/fixnum.dart';
import 'package:protobuf/protobuf.dart' show InvalidProtocolBufferException;
import 'package:zuno_http/zuno_http.dart';

import '../../network/app_http_client.dart';
import '../models/sfu_failures.dart';
import 'proto/livekit_models.pbenum.dart';
import 'proto/livekit_rtc.pb.dart';

abstract interface class LiveKitSocket {
  Stream<List<int>> get frames;
  void send(List<int> bytes);
  Future<void> close();
}

typedef LiveKitSocketConnect = Future<LiveKitSocket> Function(
  Uri url,
  Map<String, String> headers,
);

class LiveKitJoinRefused implements SfuRefusal {
  const LiveKitJoinRefused(this.reason);

  final String reason;

  @override
  bool get permanent => true;

  @override
  String toString() => 'LiveKitJoinRefused: $reason';
}

class LiveKitSignalUnreachable implements SfuUnreachable {
  const LiveKitSignalUnreachable(this.kind);

  final String kind;

  @override
  String toString() => 'LiveKitSignalUnreachable: $kind';
}

class LiveKitSignalClosed implements Exception {
  const LiveKitSignalClosed();

  @override
  String toString() => 'LiveKitSignalClosed';
}

class _ZunoSocket implements LiveKitSocket {
  _ZunoSocket(this._socket);

  final ZunoWebSocket _socket;

  @override
  Stream<List<int>> get frames => _socket.frames;

  @override
  void send(List<int> bytes) => _socket.send(bytes);

  @override
  Future<void> close() => _socket.close();
}

Future<LiveKitSocket> connectZunoSocket(
  Uri url,
  Map<String, String> headers,
) async => _ZunoSocket(await appWebSocket(url, headers));

const _protocolVersion = '16';
const _handshakeDeadline = Duration(seconds: 15);
const _defaultPingInterval = 5;
const _defaultPingTimeout = 15;

class LiveKitSignalClient {
  LiveKitSignalClient({LiveKitSocketConnect? connect})
    : _connect = connect ?? connectZunoSocket;

  final LiveKitSocketConnect _connect;
  final _responses = StreamController<SignalResponse>();
  final _lost = StreamController<void>.broadcast();

  LiveKitSocket? _socket;
  StreamSubscription<List<int>>? _subscription;
  Timer? _pingTimer;
  Timer? _pongTimer;
  var _token = '';
  var _generation = 0;
  Completer<SignalResponse>? _handshake;
  var _pingInterval = const Duration(seconds: _defaultPingInterval);
  var _pingTimeout = const Duration(seconds: _defaultPingTimeout);

  Stream<SignalResponse> get responses => _responses.stream;

  Stream<void> get lost => _lost.stream;

  Future<JoinResponse> join(Uri url, String token) async {
    _token = token;
    final first = await _open(url, const {}, SignalResponse_Message.join);
    final join = first.join;
    _startKeepalive(join.pingInterval, join.pingTimeout);
    return join;
  }

  Future<ReconnectResponse> resume(Uri url, String participantSid) async {
    final first = await _open(url, {
      'reconnect': '1',
      'sid': participantSid,
    }, SignalResponse_Message.reconnect);
    _startKeepalive(_pingInterval.inSeconds, _pingTimeout.inSeconds);
    return first.reconnect;
  }

  void send(SignalRequest request) {
    final socket = _socket;
    if (socket == null) throw StateError('The signal connection is closed.');
    socket.send(request.writeToBuffer());
  }

  void leave() {
    try {
      _socket?.send(
        SignalRequest(
          leave: LeaveRequest(reason: DisconnectReason.CLIENT_INITIATED),
        ).writeToBuffer(),
      );
    } finally {
      _teardown();
    }
  }

  Future<SignalResponse> _open(
    Uri url,
    Map<String, String> extra,
    SignalResponse_Message expected,
  ) async {
    _teardown();
    final generation = _generation;
    final SignalResponse first;
    try {
      first = await _connectAndHandshake(_rtcUri(url, extra), generation)
          .timeout(
            _handshakeDeadline,
            onTimeout: () => throw const LiveKitSignalUnreachable('no answer'),
          );
    } on Object {
      if (generation == _generation) _teardown();
      rethrow;
    }
    if (first.whichMessage() != expected) {
      _teardown();
      throw const LiveKitJoinRefused('unexpected first message');
    }
    return first;
  }

  Future<SignalResponse> _connectAndHandshake(Uri uri, int generation) async {
    final LiveKitSocket socket;
    try {
      socket = await _connect(uri, {'Authorization': 'Bearer $_token'});
    } on WebSocketUpgradeRefused catch (e) {
      throw switch (e.status) {
        final status when status >= 500 || status == 429 =>
          LiveKitSignalUnreachable('upgrade $status'),
        final status => LiveKitJoinRefused('upgrade $status'),
      };
    } on CleartextRefusedException {
      throw const LiveKitJoinRefused('cleartext');
    } on NativeHttpException catch (e) {
      throw LiveKitSignalUnreachable(e.kind.name);
    }
    if (generation != _generation) {
      socket.close().ignore();
      throw const LiveKitSignalClosed();
    }
    _socket = socket;
    final first = _handshake = Completer<SignalResponse>();
    var handshaken = false;
    void closed(String reason) {
      if (handshaken) {
        _emitLost();
      } else if (!first.isCompleted) {
        first.completeError(LiveKitSignalUnreachable(reason));
      }
    }

    _subscription = socket.frames.listen(
      (frame) {
        final SignalResponse response;
        try {
          response = SignalResponse.fromBuffer(frame);
        } on InvalidProtocolBufferException {
          return;
        }
        if (handshaken) {
          _dispatch(response);
        } else if (!first.isCompleted) {
          if (response.whichMessage() == SignalResponse_Message.leave) {
            first.completeError(LiveKitJoinRefused(response.leave.reason.name));
          } else if (response.whichMessage() == SignalResponse_Message.join ||
              response.whichMessage() == SignalResponse_Message.reconnect) {
            handshaken = true;
            first.complete(response);
          }
        }
      },
      onError: (Object _) => closed('socket error'),
      onDone: () => closed('closed before join'),
    );
    return first.future;
  }

  Uri _rtcUri(Uri base, Map<String, String> extra) => base.replace(
    pathSegments: [...base.pathSegments.where((s) => s.isNotEmpty), 'rtc'],
    queryParameters: {
      'auto_subscribe': '0',
      'adaptive_stream': '0',
      'protocol': _protocolVersion,
      'sdk': 'flutter',
      ...extra,
    },
  );

  void _dispatch(SignalResponse response) {
    switch (response.whichMessage()) {
      case SignalResponse_Message.pongResp:
      case SignalResponse_Message.pong:
        _pongTimer?.cancel();
        _pongTimer = null;
      case SignalResponse_Message.refreshToken:
        _token = response.refreshToken;
      default:
        _responses.add(response);
    }
  }

  void _startKeepalive(int intervalSeconds, int timeoutSeconds) {
    _pingInterval = Duration(
      seconds: intervalSeconds > 0 ? intervalSeconds : _defaultPingInterval,
    );
    _pingTimeout = Duration(
      seconds: timeoutSeconds > 0 ? timeoutSeconds : _defaultPingTimeout,
    );
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      send(
        SignalRequest(
          pingReq: Ping(timestamp: Int64(clock.now().millisecondsSinceEpoch)),
        ),
      );
      _pongTimer ??= Timer(_pingTimeout, _emitLost);
    });
  }

  void _emitLost() {
    if (_socket == null) return;
    _cancelTimers();
    _lost.add(null);
    _teardown();
  }

  void _cancelTimers() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _pongTimer?.cancel();
    _pongTimer = null;
  }

  void _teardown() {
    _generation++;
    _cancelTimers();
    final handshake = _handshake;
    _handshake = null;
    if (handshake != null && !handshake.isCompleted) {
      handshake.completeError(const LiveKitSignalClosed());
    }
    final subscription = _subscription;
    final socket = _socket;
    _subscription = null;
    _socket = null;
    unawaited(subscription?.cancel());
    socket?.close().ignore();
  }
}
