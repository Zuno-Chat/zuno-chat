import 'package:http/http.dart' as http;

import 'abortable_request.dart';

const refreshBound = Duration(seconds: 10);

class RefreshDeadlineHttpClient extends http.BaseClient {
  RefreshDeadlineHttpClient(this._inner, {this.deadline = refreshBound});

  final http.Client _inner;
  final Duration deadline;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request is! http.Request || !_isRefresh(request)) {
      return _inner.send(request);
    }
    return _inner.send(abortableCopy(request, Future<void>.delayed(deadline)));
  }

  @override
  void close() => _inner.close();
}

bool _isRefresh(http.Request request) =>
    request.method == 'POST' && request.url.path.endsWith('/refresh');
