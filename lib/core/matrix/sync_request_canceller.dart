import 'dart:async';

import 'package:http/http.dart' as http;

import 'abortable_request.dart';

class SyncRequestCanceller extends http.BaseClient {
  SyncRequestCanceller(this._inner);

  final http.Client _inner;
  final _waiting = <Completer<void>>{};
  bool _paused = false;

  bool cancel() {
    if (_waiting.isEmpty) return false;
    final waiting = _waiting.toList();
    _waiting.clear();
    for (final abort in waiting) {
      abort.complete();
    }
    return true;
  }

  void pause() {
    _paused = true;
    cancel();
  }

  void resume() => _paused = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is! http.Request || !_isSync(request)) {
      return _inner.send(request);
    }
    if (_paused) throw http.RequestAbortedException(request.url);
    final abort = Completer<void>();
    _waiting.add(abort);
    try {
      return await _inner.send(abortableCopy(request, abort.future));
    } finally {
      _waiting.remove(abort);
    }
  }

  @override
  void close() => _inner.close();
}

bool _isSync(http.Request request) =>
    request.method == 'GET' && request.url.path.endsWith('/sync');
