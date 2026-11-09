import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:http/http.dart' as http;

import 'failures.dart';
import 'native_http.dart';

abstract interface class RewindableBody {
  Stream<List<int>> rewoundBody();
}

Stream<List<int>> Function()? replayOf(http.BaseRequest request) =>
    switch (request) {
      final RewindableBody body => body.rewoundBody,
      final http.Request plain => () => Stream.value(plain.bodyBytes),
      _ => null,
    };

class _BodyReader {
  _BodyReader(this._stream, {required this.length, required this.uri})
    : _source = ChunkedStreamReader(_stream);

  final Stream<List<int>> _stream;
  final ChunkedStreamReader<int> _source;
  final int? length;
  final Uri uri;
  var _taken = 0;
  var _started = false;
  var _released = false;

  Future<(Uint8List, bool)> take(int max) async {
    _started = true;
    final expected = length;
    final asked = expected == null ? max : math.min(max, expected - _taken);
    final bytes = asked > 0 ? await _source.readBytes(asked) : Uint8List(0);
    _taken += bytes.length;
    final sourceEnded = bytes.length < asked;
    if (expected == null) return (bytes, sourceEnded);
    if (_taken < expected) {
      if (sourceEnded) {
        throw http.ClientException(
          'Content size below specified contentLength. '
          '$_taken bytes written but expected $expected.',
          uri,
        );
      }
      return (bytes, false);
    }
    if ((await _source.readBytes(1)).isNotEmpty) {
      throw http.ClientException(
        'Content size exceeds specified contentLength. '
        'More than $expected bytes written while expected $expected.',
        uri,
      );
    }
    return (bytes, true);
  }

  Future<void> release() async {
    if (_released) return;
    _released = true;
    if (_started) {
      await _source.cancel();
    } else {
      await _stream.listen(null).cancel();
    }
  }
}

class RequestBodyPump {
  RequestBodyPump({
    required this._native,
    required this._id,
    required this._body,
    required this._replay,
    required this._length,
    required this._uri,
    required this._onProgress,
    required this._onFailure,
  });

  final NativeHttp _native;
  final int _id;
  final Stream<List<int>> _body;
  final Stream<List<int>> Function()? _replay;
  final int? _length;
  final Uri _uri;
  final void Function() _onProgress;
  final void Function(Object error) _onFailure;
  late var _reader = _BodyReader(_body, length: _length, uri: _uri);
  var _stopped = false;

  void stop() {
    if (_stopped) return;
    _stopped = true;
    unawaited(_reader.release());
  }

  Future<void> run() async {
    try {
      await _pumpUntilDone();
    } on Object catch (error) {
      _onFailure(error);
    } finally {
      unawaited(_reader.release());
    }
  }

  Future<void> _pumpUntilDone() async {
    BodyPull pull;
    try {
      pull = await _native.pullBody(_id);
    } on Object {
      return;
    }
    while (!_stopped) {
      switch (pull) {
        case BodyDone():
          return;
        case Rewind():
          final replay = _replay;
          if (replay == null) {
            throw NativeHttpException(
              HttpFailureKind.connectionLost,
              'The connection dropped and the request body cannot be sent again',
              _uri,
            );
          }
          unawaited(_reader.release());
          _reader = _BodyReader(replay(), length: _length, uri: _uri);
          try {
            pull = await _native.pullBody(_id);
          } on Object {
            return;
          }
        case WantBytes(:final max):
          final (bytes, last) = await _reader.take(max);
          if (_stopped) return;
          final answer = _native.write(_id, bytes, last: last);
          _onProgress();
          try {
            pull = await answer;
          } on Object {
            return;
          }
          _onProgress();
      }
    }
  }
}
