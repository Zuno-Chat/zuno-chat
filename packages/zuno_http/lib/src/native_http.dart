import 'dart:typed_data';

enum NativePhase { connecting, waiting, unknown }

class NativeRequest {
  const NativeRequest({
    required this.id,
    required this.method,
    required this.url,
    required this.headers,
    required this.hasBody,
    this.bodyLength,
  });

  final int id;
  final String method;
  final Uri url;
  final Map<String, String> headers;
  final int? bodyLength;
  final bool hasBody;
}

class NativeHead {
  const NativeHead({required this.status, required this.headers, this.reason});

  final int status;
  final String? reason;
  final Map<String, List<String>> headers;
}

final class NativeChunk {
  const NativeChunk({this.bytes, this.end = false, this.protocol});

  final Uint8List? bytes;
  final bool end;
  final String? protocol;
}

sealed class BodyPull {
  const BodyPull();
}

final class WantBytes extends BodyPull {
  const WantBytes(this.max);

  final int max;
}

final class Rewind extends BodyPull {
  const Rewind();
}

final class BodyDone extends BodyPull {
  const BodyDone();
}

abstract interface class NativeHttp {
  Future<void> ready();

  Future<NativeHead> open(NativeRequest request);

  Future<BodyPull> pullBody(int id);

  Future<BodyPull> write(int id, Uint8List chunk, {required bool last});

  Future<NativeChunk> read(int id);

  Future<NativePhase> status(int id);

  Future<void> cancel(int id);
}

abstract interface class NativeWebSocket {
  Future<void> connect(int id, Uri url, Map<String, String> headers);

  Future<Uint8List?> receive(int id);

  Future<bool> send(int id, Uint8List bytes);

  Future<void> close(int id);
}
