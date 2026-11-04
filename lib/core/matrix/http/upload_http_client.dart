import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'abortable_request.dart';

const _uploadPath = '/_matrix/media/v3/upload';

const _chunkSize = 64 * 1024;

const sendStallLimit = Duration(seconds: 30);

final _scopeKey = Object();

class SendScope {
  SendScope({this._onProgress});

  final void Function(double fraction)? _onProgress;
  final _stop = Completer<void>();
  Object? _failure;

  Object? get failure => _failure;

  bool get isStopped => _stop.isCompleted;

  Future<void> get stopped => _stop.future;

  void stop() {
    if (!_stop.isCompleted) _stop.complete();
  }

  Future<T> run<T>(Future<T> Function() body) =>
      runZoned(body, zoneValues: {_scopeKey: this});
}

class UploadHttpClient extends http.BaseClient {
  UploadHttpClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request is! http.Request) return _inner.send(request);
    final scope = Zone.current[_scopeKey] as SendScope?;
    if (request.method == 'POST' && request.url.path == _uploadPath) {
      return _rememberingFailure(scope, () => _sendUpload(request, scope));
    }
    if (scope == null) return _inner.send(request);
    return _rememberingFailure(scope, () => _sendAwaitingAnswer(request));
  }

  Future<http.StreamedResponse> _rememberingFailure(
    SendScope? scope,
    Future<http.StreamedResponse> Function() send,
  ) async {
    try {
      return await send();
    } catch (error) {
      scope?._failure = error;
      rethrow;
    }
  }

  Future<http.StreamedResponse> _sendUpload(
    http.Request request,
    SendScope? scope,
  ) async {
    if (scope != null && scope.isStopped) {
      throw http.RequestAbortedException(request.url);
    }
    final upload = _WatchedUpload(request, scope);
    try {
      return await _inner.send(upload);
    } on http.RequestAbortedException {
      if (!upload.stalled) rethrow;
      throw _noProgress(request);
    } finally {
      upload.answered();
    }
  }

  Future<http.StreamedResponse> _sendAwaitingAnswer(
    http.Request request,
  ) async {
    final stalled = Completer<void>();
    final watchdog = Timer(sendStallLimit, stalled.complete);
    try {
      return await _inner.send(abortableCopy(request, stalled.future));
    } on http.RequestAbortedException {
      if (!stalled.isCompleted) rethrow;
      throw _noProgress(request);
    } finally {
      watchdog.cancel();
    }
  }

  @override
  void close() => _inner.close();
}

http.ClientException _noProgress(http.BaseRequest request) =>
    http.ClientException(
      'No progress for ${sendStallLimit.inSeconds} s',
      request.url,
    );

class _WatchedUpload extends http.BaseRequest implements http.Abortable {
  _WatchedUpload(this._inner, this._scope) : super(_inner.method, _inner.url) {
    headers.addAll(_inner.headers);
    followRedirects = _inner.followRedirects;
    maxRedirects = _inner.maxRedirects;
    persistentConnection = _inner.persistentConnection;
    contentLength = _inner.contentLength;
    unawaited(_scope?.stopped.whenComplete(_abort));
    _watch();
  }

  final http.Request _inner;
  final SendScope? _scope;
  final _aborted = Completer<void>();
  Timer? _watchdog;
  var stalled = false;

  @override
  Future<void> get abortTrigger => _aborted.future;

  void answered() => _watchdog?.cancel();

  void _abort() {
    _watchdog?.cancel();
    if (!_aborted.isCompleted) _aborted.complete();
  }

  void _watch() {
    _watchdog?.cancel();
    _watchdog = Timer(sendStallLimit, () {
      stalled = true;
      _abort();
    });
  }

  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_chunked(_inner.bodyBytes));
  }

  Stream<List<int>> _chunked(Uint8List bytes) async* {
    final total = bytes.length;
    var offset = 0;
    while (offset < total) {
      final end = offset + _chunkSize < total ? offset + _chunkSize : total;
      yield bytes.sublist(offset, end);
      offset = end;
      _watch();
      _scope?._onProgress?.call(offset / total);
    }
  }
}
