import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:zstandard/zstandard.dart';

typedef ZstdDecompressor = Future<Uint8List?> Function(Uint8List data);

class ZstdResponseHttpClient extends http.BaseClient {
  ZstdResponseHttpClient(this._inner, {ZstdDecompressor? decompress})
    : _decompress = decompress ?? Zstandard().decompress;

  final http.Client _inner;
  final ZstdDecompressor _decompress;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers['accept-encoding'] = _withZstd(
      request.headers['accept-encoding'],
    );

    final response = await _inner.send(request);
    if ((response.headers['content-encoding'] ?? '').toLowerCase() !=
        'zstd') {
      return response;
    }

    final compressed = await response.stream.toBytes();
    final decompressed = await _decompress(compressed);
    if (decompressed == null) {
      throw http.ClientException(
        'zstd response decompression failed',
        request.url,
      );
    }

    final headers = Map<String, String>.from(response.headers)
      ..remove('content-encoding')
      ..['content-length'] = decompressed.length.toString();

    return http.StreamedResponse(
      http.ByteStream.fromBytes(decompressed),
      response.statusCode,
      contentLength: decompressed.length,
      request: response.request,
      headers: headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();

  static String _withZstd(String? existing) {
    if (existing == null || existing.isEmpty) return 'zstd';
    final alreadyPresent = existing
        .split(',')
        .map((e) => e.trim().toLowerCase())
        .contains('zstd');
    return alreadyPresent ? existing : '$existing, zstd';
  }
}
