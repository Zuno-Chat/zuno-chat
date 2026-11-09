import 'dart:async';

import 'failures.dart';
import 'native_http.dart';

const unlistenedBodyLimit = Duration(seconds: 30);

class ResponseBody {
  ResponseBody({
    required this._native,
    required this._id,
    required this._uri,
    required this._onEnd,
    required this._onFailure,
    required this._onCancel,
    this._idle,
  }) {
    _controller = StreamController(
      onListen: _listened,
      onPause: _paused,
      onResume: _resumed,
      onCancel: _cancelled,
    );
    _unlistened = Timer(
      unlistenedBodyLimit,
      () => _timeOut(
        'Response body not read within ${unlistenedBodyLimit.inSeconds} s',
      ),
    );
  }

  final NativeHttp _native;
  final int _id;
  final Uri _uri;
  final void Function(String? protocol) _onEnd;
  final Object Function(Object error) _onFailure;
  final void Function() _onCancel;
  final Duration? _idle;
  late final StreamController<List<int>> _controller;
  Timer? _idleTimer;
  late final Timer _unlistened;
  var _reading = false;
  var _done = false;

  Stream<List<int>> get stream => _controller.stream;

  void fail(Object error) {
    if (_done) return;
    _done = true;
    _unlistened.cancel();
    _idleTimer?.cancel();
    _controller
      ..addError(error)
      ..close();
  }

  void _listened() {
    _unlistened.cancel();
    _pump();
  }

  void _pump() {
    if (_reading || _done || _controller.isPaused) return;
    _reading = true;
    _startIdle();
    _native.read(_id).then(_received, onError: _failed);
  }

  void _startIdle() {
    _idleTimer?.cancel();
    final idle = _idle;
    if (idle != null) {
      _idleTimer = Timer(
        idle,
        () => _timeOut('No data for ${idle.inSeconds} s'),
      );
    }
  }

  void _paused() => _idleTimer?.cancel();

  void _resumed() {
    if (_reading && !_done) _startIdle();
    _pump();
  }

  void _received(NativeChunk chunk) {
    _reading = false;
    _idleTimer?.cancel();
    if (_done) return;
    final bytes = chunk.bytes;
    if (bytes != null && bytes.isNotEmpty) _controller.add(bytes);
    if (!chunk.end) {
      _pump();
      return;
    }
    _done = true;
    _onEnd(chunk.protocol);
    _controller.close();
  }

  void _failed(Object error) {
    _reading = false;
    _idleTimer?.cancel();
    if (!_done) fail(_onFailure(error));
  }

  void _timeOut(String why) {
    fail(NativeHttpException(HttpFailureKind.timedOut, why, _uri));
    _onCancel();
  }

  void _cancelled() {
    _unlistened.cancel();
    _idleTimer?.cancel();
    if (_done) return;
    _done = true;
    _onCancel();
  }
}
