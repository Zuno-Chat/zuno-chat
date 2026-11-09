import 'dart:async';
import 'dart:typed_data';

import 'channel_native_http.dart';
import 'cleartext.dart';
import 'failures.dart';
import 'headers.dart';
import 'native_http.dart';

const webSocketConnectLimit = Duration(seconds: 15);

var _nextSocketId = 1;

class ZunoWebSocket {
  ZunoWebSocket._(this._native, this._id, this._url) {
    _frames = StreamController(
      onListen: _receive,
      onResume: _receive,
      onCancel: close,
    );
  }

  static Future<ZunoWebSocket> connect(
    Uri url, {
    Map<String, String> headers = const {},
    required String userAgent,
    NativeWebSocket? native,
  }) async {
    if (cleartextRefusal(url, secureScheme: 'wss') case final refusal?) {
      throw refusal;
    }
    final sockets = native ?? ChannelNativeWebSocket.instance;
    final id = _nextSocketId++;
    try {
      await sockets
          .connect(id, url, withUserAgent(headers, userAgent))
          .timeout(webSocketConnectLimit);
    } on TimeoutException {
      sockets.close(id).catchError((Object _) {}).ignore();
      throw NativeHttpException(
        HttpFailureKind.timedOut,
        'No WebSocket upgrade within ${webSocketConnectLimit.inSeconds} s',
        url,
      );
    }
    return ZunoWebSocket._(sockets, id, url);
  }

  final NativeWebSocket _native;
  final int _id;
  final Uri _url;
  late final StreamController<List<int>> _frames;
  var _receiving = false;
  var _closed = false;

  Stream<List<int>> get frames => _frames.stream;

  void send(List<int> bytes) {
    if (_closed) throw StateError('The WebSocket is closed.');
    final frame = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    _native.send(_id, frame).then((accepted) {
      if (!accepted) {
        _lose(
          NativeHttpException(
            HttpFailureKind.connectionLost,
            'The WebSocket refused a frame',
            _url,
          ),
        );
      }
    }, onError: _lose).ignore();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (!_frames.isClosed) unawaited(_frames.close());
    await _native.close(_id).catchError((Object _) {});
  }

  void _receive() {
    if (_receiving || _closed || _frames.isPaused || !_frames.hasListener) {
      return;
    }
    _receiving = true;
    _native
        .receive(_id)
        .then(
          (frame) {
            _receiving = false;
            if (_closed) return;
            if (frame == null) {
              _closed = true;
              _frames.close();
              return;
            }
            _frames.add(frame);
            _receive();
          },
          onError: (Object error) {
            _receiving = false;
            _lose(error);
          },
        )
        .ignore();
  }

  void _lose(Object error) {
    if (_closed) return;
    _frames.addError(error);
    close().ignore();
  }
}
