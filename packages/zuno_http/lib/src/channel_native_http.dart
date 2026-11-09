import 'package:flutter/services.dart';

import 'cleartext.dart';
import 'failures.dart';
import 'native_http.dart';

final _kinds = HttpFailureKind.values.asNameMap();
final _phases = NativePhase.values.asNameMap();

Object _failure(PlatformException error, Uri? uri) {
  final detail = error.message ?? error.code;
  return switch (error.code) {
    'upgrade' when error.details is int => WebSocketUpgradeRefused(
      error.details as int,
    ),
    'engineUnavailable' => NativeEngineUnavailable(detail),
    'cleartext' => CleartextRefusedException(uri ?? Uri()),
    final code => NativeHttpException(
      _kinds[code] ?? HttpFailureKind.protocol,
      _kinds.containsKey(code) ? detail : '$code: $detail',
      uri,
    ),
  };
}

Future<T?> _invoke<T>(
  MethodChannel channel,
  String method,
  Object? arguments, {
  Uri? uri,
}) async {
  try {
    return await channel.invokeMethod<T>(method, arguments);
  } on PlatformException catch (error) {
    throw _failure(error, uri);
  }
}

BodyPull _pull(Map<Object?, Object?>? reply) => switch (reply) {
  {'rewind': true} => const Rewind(),
  {'want': final int max} => WantBytes(max),
  _ => const BodyDone(),
};

class ChannelNativeHttp implements NativeHttp {
  ChannelNativeHttp._(this._channel);

  static final instance = ChannelNativeHttp._(const MethodChannel('zuno/http'));

  final MethodChannel _channel;

  @override
  Future<void> ready() => _invoke<void>(_channel, 'ready', null);

  @override
  Future<NativeHead> open(NativeRequest request) async {
    final reply = await _invoke<Map<Object?, Object?>>(_channel, 'open', {
      'id': request.id,
      'method': request.method,
      'url': request.url.toString(),
      'headers': request.headers,
      'bodyLength': request.bodyLength,
      'hasBody': request.hasBody,
    }, uri: request.url);
    try {
      return NativeHead(
        status: reply!['status']! as int,
        reason: reply['reason'] as String?,
        headers: {
          for (final MapEntry(:key, :value)
              in (reply['headers']! as Map<Object?, Object?>).entries)
            key! as String: [
              for (final item in value! as List<Object?>) item! as String,
            ],
        },
      );
    } on TypeError catch (error) {
      throw NativeHttpException(
        HttpFailureKind.protocol,
        'Malformed response head: $error',
        request.url,
      );
    }
  }

  @override
  Future<BodyPull> pullBody(int id) async =>
      _pull(await _invoke(_channel, 'pullBody', {'id': id}));

  @override
  Future<BodyPull> write(int id, Uint8List chunk, {required bool last}) async =>
      _pull(
        await _invoke(_channel, 'write', {
          'id': id,
          'chunk': chunk,
          'last': last,
        }),
      );

  @override
  Future<NativeChunk> read(int id) async {
    final reply = await _invoke<Object>(_channel, 'read', {'id': id});
    return switch (reply) {
      final Uint8List bytes => NativeChunk(bytes: bytes),
      final Map<Object?, Object?> end => NativeChunk(
        bytes: end['bytes'] as Uint8List?,
        end: end['end'] == true,
        protocol: end['protocol'] as String?,
      ),
      _ => const NativeChunk(end: true),
    };
  }

  @override
  Future<NativePhase> status(int id) async =>
      _phases[await _invoke<String>(_channel, 'status', {'id': id})] ??
      NativePhase.unknown;

  @override
  Future<void> cancel(int id) => _invoke<void>(_channel, 'cancel', {'id': id});
}

class ChannelNativeWebSocket implements NativeWebSocket {
  ChannelNativeWebSocket._(this._channel);

  static final instance = ChannelNativeWebSocket._(
    const MethodChannel('zuno/websocket'),
  );

  final MethodChannel _channel;

  @override
  Future<void> connect(int id, Uri url, Map<String, String> headers) =>
      _invoke<void>(_channel, 'connect', {
        'id': id,
        'url': url.toString(),
        'headers': headers,
      }, uri: url);

  @override
  Future<Uint8List?> receive(int id) =>
      _invoke<Uint8List>(_channel, 'receive', {'id': id});

  @override
  Future<bool> send(int id, Uint8List bytes) async =>
      await _invoke<bool>(_channel, 'send', {'id': id, 'bytes': bytes}) ??
      false;

  @override
  Future<void> close(int id) => _invoke<void>(_channel, 'close', {'id': id});
}
