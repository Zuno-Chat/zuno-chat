import 'dart:async';
import 'dart:io' show HandshakeException, SocketException, WebSocketException;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/calls/livekit/livekit_signal_client.dart';
import 'package:zuno/core/calls/livekit/proto/livekit_models.pbenum.dart';
import 'package:zuno/core/calls/livekit/proto/livekit_rtc.pb.dart';

import 'fake_livekit_socket.dart';

final _url = Uri.parse('wss://lk.example.org');
const _token = 'lk.secret.token';

SignalResponse _join({int pingInterval = 5, int pingTimeout = 15}) =>
    SignalResponse(
      join: JoinResponse(pingInterval: pingInterval, pingTimeout: pingTimeout),
    );

({LiveKitSignalClient client, FakeLiveKitServer server}) _setup({
  SignalResponse? first,
}) {
  final server = FakeLiveKitServer()
    ..onConnect = (socket) =>
        Future<void>.microtask(() => socket.serverSends(first ?? _join()));
  return (client: LiveKitSignalClient(connect: server.connect), server: server);
}

void _joined(
  void Function(
    FakeAsync async,
    LiveKitSignalClient client,
    FakeLiveKitServer server,
  )
  body, {
  Uri? url,
}) => fakeAsync((async) {
  final (:client, :server) = _setup();
  client.join(url ?? _url, _token);
  async.flushMicrotasks();
  body(async, client, server);
  client.leave();
  async.flushMicrotasks();
  expect(async.periodicTimerCount, 0);
});

void main() {
  test('join sends the bearer header and the protocol query, and no token in '
      'the URL', () {
    _joined((async, client, server) {
      final connect = server.connects.single;
      expect(connect.headers, {'Authorization': 'Bearer $_token'});
      expect(connect.url.scheme, 'wss');
      expect(connect.url.host, 'lk.example.org');
      expect(connect.url.path, '/rtc');
      expect(connect.url.queryParameters, {
        'auto_subscribe': '0',
        'adaptive_stream': '0',
        'protocol': '16',
        'sdk': 'flutter',
      });
      expect(connect.url.toString(), isNot(contains(_token)));
    });
  });

  test('a base url with a path keeps it before /rtc', () {
    _joined((async, client, server) {
      expect(server.connects.single.url.path, '/prefix/rtc');
    }, url: Uri.parse('wss://lk.example.org/prefix/'));
  });

  test('join returns the JoinResponse', () {
    fakeAsync((async) {
      final (:client, server: _) = _setup();
      JoinResponse? join;
      client.join(_url, _token).then((value) => join = value);
      async.flushMicrotasks();

      expect(join?.pingInterval, 5);
      client.leave();
    });
  });

  test('upgrade 401 throws LiveKitJoinRefused', () async {
    final (:client, :server) = _setup();
    server.connectError = const WebSocketException(
      "Connection to 'wss://lk.example.org/rtc?protocol=16' was not upgraded "
      'to websocket',
      401,
    );

    await expectLater(
      client.join(_url, _token),
      throwsA(
        isA<LiveKitJoinRefused>()
            .having((e) => e.reason, 'reason', 'upgrade 401')
            .having((e) => e.toString(), 'text', isNot(contains('lk.example'))),
      ),
    );
  });

  for (final status in [429, 500, 503]) {
    test('upgrade $status is unreachable, so it is tried again', () async {
      final (:client, :server) = _setup();
      server.connectError = WebSocketException('not upgraded', status);

      await expectLater(
        client.join(_url, _token),
        throwsA(
          isA<LiveKitSignalUnreachable>().having(
            (e) => e.kind,
            'kind',
            'upgrade $status',
          ),
        ),
      );
    });
  }

  for (final (name, error) in <(String, Object)>[
    ('SocketException', const SocketException('lk.example.org')),
    ('HandshakeException', const HandshakeException('lk.example.org')),
    (
      'WebSocketException',
      const WebSocketException(
        "Connection to 'wss://lk.example.org/rtc' failed",
      ),
    ),
  ]) {
    test('a $name is unreachable, and its text names no host', () async {
      final (:client, :server) = _setup();
      server.connectError = error;

      await expectLater(
        client.join(_url, _token),
        throwsA(
          isA<LiveKitSignalUnreachable>().having(
            (e) => e.toString(),
            'text',
            allOf(contains(name), isNot(contains('lk.example'))),
          ),
        ),
      );
    });
  }

  test('a first leave JOIN_FAILURE throws LiveKitJoinRefused', () async {
    final (:client, server: _) = _setup(
      first: SignalResponse(
        leave: LeaveRequest(reason: DisconnectReason.JOIN_FAILURE),
      ),
    );

    await expectLater(
      client.join(_url, _token),
      throwsA(
        isA<LiveKitJoinRefused>().having(
          (e) => e.reason,
          'reason',
          'JOIN_FAILURE',
        ),
      ),
    );
  });

  test('a socket that closes before the join is unreachable', () async {
    final server = FakeLiveKitServer()
      ..onConnect = (socket) => Future<void>.microtask(socket.serverCloses);
    final client = LiveKitSignalClient(connect: server.connect);

    await expectLater(
      client.join(_url, _token),
      throwsA(
        isA<LiveKitSignalUnreachable>().having(
          (e) => e.kind,
          'kind',
          'closed before join',
        ),
      ),
    );
  });

  test('a socket error before the join is unreachable', () async {
    final server = FakeLiveKitServer()
      ..onConnect = (socket) => Future<void>.microtask(socket.serverFails);
    final client = LiveKitSignalClient(connect: server.connect);

    await expectLater(
      client.join(_url, _token),
      throwsA(
        isA<LiveKitSignalUnreachable>().having(
          (e) => e.kind,
          'kind',
          'socket error',
        ),
      ),
    );
  });

  test('a server that never answers the join is unreachable', () {
    fakeAsync((async) {
      final server = FakeLiveKitServer();
      final client = LiveKitSignalClient(connect: server.connect);
      Object? error;
      client.join(_url, _token).catchError((Object e) {
        error = e;
        return JoinResponse();
      });

      async.elapse(const Duration(seconds: 14));
      expect(error, isNull);
      async.elapse(const Duration(seconds: 2));

      expect(
        error,
        isA<LiveKitSignalUnreachable>().having(
          (e) => e.kind,
          'kind',
          'no answer',
        ),
      );
      expect(server.socket.closed, isTrue);
    });
  });

  test('a leave while the socket connects closes the socket that lands, and '
      'the join throws', () {
    fakeAsync((async) {
      final server = FakeLiveKitServer();
      final connecting = Completer<void>();
      Future<LiveKitSocket> connect(
        Uri url,
        Map<String, String> headers,
      ) async {
        await connecting.future;
        return server.connect(url, headers);
      }

      final client = LiveKitSignalClient(connect: connect);
      Object? error;
      client.join(_url, _token).catchError((Object e) {
        error = e;
        return JoinResponse();
      });
      async.flushMicrotasks();

      client.leave();
      connecting.complete();
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 1));

      expect(error, isA<LiveKitSignalClosed>());
      expect(server.socket.closed, isTrue);
      expect(server.socket.sent, isEmpty);
    });
  });

  test('a leave during the handshake ends the join at once', () {
    fakeAsync((async) {
      final server = FakeLiveKitServer();
      final client = LiveKitSignalClient(connect: server.connect);
      Object? error;
      client.join(_url, _token).catchError((Object e) {
        error = e;
        return JoinResponse();
      });
      async.flushMicrotasks();

      client.leave();
      async.flushMicrotasks();

      expect(error, isA<LiveKitSignalClosed>());
      expect(server.socket.closed, isTrue);
    });
  });

  test('one deadline covers the connect and the handshake', () {
    fakeAsync((async) {
      final server = FakeLiveKitServer();
      final connecting = Completer<void>();
      Future<LiveKitSocket> connect(
        Uri url,
        Map<String, String> headers,
      ) async {
        await connecting.future;
        return server.connect(url, headers);
      }

      final client = LiveKitSignalClient(connect: connect);
      Object? error;
      client.join(_url, _token).catchError((Object e) {
        error = e;
        return JoinResponse();
      });

      async.elapse(const Duration(seconds: 15));
      expect(
        error,
        isA<LiveKitSignalUnreachable>().having(
          (e) => e.kind,
          'kind',
          'no answer',
        ),
      );

      connecting.complete();
      async.flushMicrotasks();
      expect(server.socket.closed, isTrue);
    });
  });

  test('frames after the join reach responses, even before a listener', () {
    _joined((async, client, server) {
      server.socket.serverSends(
        SignalResponse(
          leave: LeaveRequest(reason: DisconnectReason.PARTICIPANT_REMOVED),
        ),
      );
      async.flushMicrotasks();

      SignalResponse? response;
      client.responses.first.then((value) => response = value);
      async.flushMicrotasks();

      expect(response?.whichMessage(), SignalResponse_Message.leave);
    });
  });

  test('send writes the request as one binary frame', () {
    _joined((async, client, server) {
      client.send(
        SignalRequest(mute: MuteTrackRequest(sid: 'TR_1', muted: true)),
      );

      expect(server.socket.sent.single.mute.sid, 'TR_1');
    });
  });

  test('missing pong within ping_timeout emits lost once', () {
    fakeAsync((async) {
      final (:client, :server) = _setup();
      var lost = 0;
      client.lost.listen((_) => lost++);
      client.join(_url, _token);
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 5));
      expect(server.socket.sentOf(SignalRequest_Message.pingReq), hasLength(1));
      async.elapse(const Duration(seconds: 14));
      expect(lost, 0);
      async.elapse(const Duration(seconds: 1));
      expect(lost, 1);
      async.elapse(const Duration(minutes: 1));
      expect(lost, 1);
    });
  });

  test('a pong keeps the connection alive', () {
    fakeAsync((async) {
      final (:client, :server) = _setup();
      var lost = 0;
      client.lost.listen((_) => lost++);
      client.join(_url, _token);
      async.flushMicrotasks();

      for (var i = 0; i < 6; i++) {
        async.elapse(const Duration(seconds: 5));
        server.socket.serverSends(SignalResponse(pongResp: Pong()));
        async.flushMicrotasks();
      }

      expect(server.socket.sentOf(SignalRequest_Message.pingReq), hasLength(6));
      expect(lost, 0);
    });
  });

  test('a socket close emits lost once', () {
    fakeAsync((async) {
      final (:client, :server) = _setup();
      var lost = 0;
      client.lost.listen((_) => lost++);
      client.join(_url, _token);
      async.flushMicrotasks();

      server.socket.serverCloses();
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 1));

      expect(lost, 1);
    });
  });

  test('leave sends CLIENT_INITIATED and emits no lost', () {
    fakeAsync((async) {
      final (:client, :server) = _setup();
      var lost = 0;
      client.lost.listen((_) => lost++);
      client.join(_url, _token);
      async.flushMicrotasks();

      client.leave();
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 1));

      final leave = server.socket.sentOf(SignalRequest_Message.leave).single;
      expect(leave.leave.reason, DisconnectReason.CLIENT_INITIATED);
      expect(server.socket.closed, isTrue);
      expect(lost, 0);
    });
  });

  test('leave tears the socket down even when the leave cannot be sent', () {
    fakeAsync((async) {
      final (:client, :server) = _setup();
      client.join(_url, _token);
      async.flushMicrotasks();
      server.socket.sendError = StateError('closed');

      Object? error;
      Future.sync(client.leave).catchError((Object e) => error = e);
      async.flushMicrotasks();

      expect(error, isStateError);
      expect(server.socket.closed, isTrue);
      expect(async.periodicTimerCount, 0);
    });
  });

  test('resume adds reconnect and sid, and sends the refreshed token', () {
    _joined((async, client, server) {
      server.socket.serverSends(SignalResponse(refreshToken: 'lk.fresh'));
      async.flushMicrotasks();
      server.onConnect = (socket) => Future<void>.microtask(
        () =>
            socket.serverSends(SignalResponse(reconnect: ReconnectResponse())),
      );

      ReconnectResponse? reconnect;
      client.resume(_url, 'PA_me').then((value) => reconnect = value);
      async.flushMicrotasks();

      expect(reconnect, isA<ReconnectResponse>());
      final connect = server.connects.last;
      expect(connect.url.queryParameters, {
        'auto_subscribe': '0',
        'adaptive_stream': '0',
        'protocol': '16',
        'sdk': 'flutter',
        'reconnect': '1',
        'sid': 'PA_me',
      });
      expect(connect.headers, {'Authorization': 'Bearer lk.fresh'});
      expect(server.sockets.first.closed, isTrue);
    });
  });

  test('closing the replaced socket does not emit lost', () {
    fakeAsync((async) {
      final (:client, :server) = _setup();
      var lost = 0;
      client.lost.listen((_) => lost++);
      client.join(_url, _token);
      async.flushMicrotasks();
      server.onConnect = (socket) => Future<void>.microtask(
        () =>
            socket.serverSends(SignalResponse(reconnect: ReconnectResponse())),
      );

      client.resume(_url, 'PA_me');
      async.flushMicrotasks();

      expect(lost, 0);
    });
  });
}
