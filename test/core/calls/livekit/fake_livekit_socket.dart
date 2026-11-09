import 'dart:async';

import 'package:zuno/core/calls/livekit/livekit_signal_client.dart';
import 'package:zuno/core/calls/livekit/proto/livekit_rtc.pb.dart';
import 'package:zuno_http/zuno_http.dart';

class FakeLiveKitSocket implements LiveKitSocket {
  final _frames = StreamController<List<int>>();
  final sent = <SignalRequest>[];
  var closed = false;
  Object? sendError;
  Completer<void>? closeGate;

  @override
  Stream<List<int>> get frames => _frames.stream;

  @override
  void send(List<int> bytes) {
    if (sendError case final error?) throw error;
    sent.add(SignalRequest.fromBuffer(bytes));
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    unawaited(_frames.close());
    await closeGate?.future;
  }

  void serverSends(SignalResponse response) =>
      _frames.add(response.writeToBuffer());

  Future<void> serverCloses() => _frames.close();

  void serverFails() => _frames.addError(
    NativeHttpException(HttpFailureKind.connectionLost, 'reset'),
  );

  Iterable<SignalRequest> sentOf(SignalRequest_Message kind) =>
      sent.where((request) => request.whichMessage() == kind);
}

abstract class LiveKitTestServer<S extends FakeLiveKitSocket> {
  final sockets = <S>[];
  final connects = <({Uri url, Map<String, String> headers})>[];
  final connectErrors = <Object>[];
  Object? connectError;
  Completer<void>? connectGate;

  S get socket => sockets.last;

  S newSocket(Uri url);

  void opened(S socket) {}

  Future<LiveKitSocket> connect(Uri url, Map<String, String> headers) async {
    connects.add((url: url, headers: headers));
    await connectGate?.future;
    if (connectErrors.isNotEmpty) throw connectErrors.removeAt(0);
    if (connectError case final error?) throw error;
    final socket = newSocket(url);
    sockets.add(socket);
    opened(socket);
    return socket;
  }
}

class FakeLiveKitServer extends LiveKitTestServer<FakeLiveKitSocket> {
  void Function(FakeLiveKitSocket socket)? onConnect;

  @override
  FakeLiveKitSocket newSocket(Uri url) => FakeLiveKitSocket();

  @override
  void opened(FakeLiveKitSocket socket) => onConnect?.call(socket);
}
