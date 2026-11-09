import 'dart:async';
import 'dart:typed_data';

import 'package:zuno_http/testing.dart';
import 'package:zuno_http/zuno_http.dart';

class ScriptedNativeWebSocket implements NativeWebSocket {
  Object? connectFailure;
  Completer<void>? holdConnect;
  Object? sendFailure;
  var sendAccepted = true;
  final attempted = <int>[];
  final connected = <int, (Uri, Map<String, String>)>{};
  final frames = Answers<Uint8List?>();
  final sent = <List<int>>[];
  final closed = <int>[];
  var receives = 0;

  int get id => connected.keys.single;

  @override
  Future<void> connect(int id, Uri url, Map<String, String> headers) async {
    attempted.add(id);
    await holdConnect?.future;
    final failure = connectFailure;
    if (failure != null) throw failure;
    connected[id] = (url, headers);
  }

  @override
  Future<Uint8List?> receive(int id) {
    receives++;
    return frames.next();
  }

  @override
  Future<bool> send(int id, Uint8List bytes) async {
    sent.add(bytes);
    final failure = sendFailure;
    if (failure != null) throw failure;
    return sendAccepted;
  }

  @override
  Future<void> close(int id) async => closed.add(id);

  void frame(List<int> bytes) => frames.answer(Uint8List.fromList(bytes));

  void closedByServer() => frames.answer(null);

  void drop(HttpFailureKind kind) =>
      frames.fail(NativeHttpException(kind, kind.name));
}
