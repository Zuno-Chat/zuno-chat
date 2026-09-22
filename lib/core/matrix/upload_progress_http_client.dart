import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

const _uploadPath = '/_matrix/media/v3/upload';

const _chunkSize = 64 * 1024;

class UploadProgressHttpClient extends http.BaseClient {
  UploadProgressHttpClient(this._inner);

  final http.Client _inner;
  final _progressController = StreamController<double>.broadcast();

  Stream<double> get onUploadProgress => _progressController.stream;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.method != 'POST' || request.url.path != _uploadPath) {
      return _inner.send(request);
    }
    return _inner.send(
      _ProgressTrackingRequest(request, _progressController.add),
    );
  }

  @override
  void close() {
    _inner.close();
    unawaited(_progressController.close());
  }
}

class _ProgressTrackingRequest extends http.BaseRequest {
  _ProgressTrackingRequest(this._inner, this._onProgress)
    : super(_inner.method, _inner.url) {
    headers.addAll(_inner.headers);
    followRedirects = _inner.followRedirects;
    maxRedirects = _inner.maxRedirects;
    persistentConnection = _inner.persistentConnection;
    contentLength = _inner.contentLength;
  }

  final http.BaseRequest _inner;
  final void Function(double fraction) _onProgress;

  @override
  http.ByteStream finalize() {
    super.finalize();
    final inner = _inner;
    if (inner is! http.Request) return inner.finalize();
    return http.ByteStream(_chunked(inner.bodyBytes));
  }

  Stream<List<int>> _chunked(Uint8List bytes) async* {
    final total = bytes.length;
    if (total == 0) return;
    var offset = 0;
    while (offset < total) {
      final end = offset + _chunkSize < total ? offset + _chunkSize : total;
      yield bytes.sublist(offset, end);
      offset = end;
      _onProgress(offset / total);
    }
  }
}
