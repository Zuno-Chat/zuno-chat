import 'package:http/http.dart' as http;

import 'abortable_request.dart';

const refreshBound = Duration(seconds: 10);

class RefreshDeadlineHttpClient extends http.BaseClient {
  RefreshDeadlineHttpClient(this._inner, {this.deadline = refreshBound});

  final http.Client _inner;
  final Duration deadline;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request is! http.Request || !_isBoundedByRefresh(request)) {
      return _inner.send(request);
    }
    return _inner.send(abortableCopy(request, Future<void>.delayed(deadline)));
  }

  @override
  void close() => _inner.close();
}

bool _isBoundedByRefresh(http.Request request) {
  if (request.method == 'GET') {
    return request.url.path.endsWith('/_matrix/client/v1/auth_metadata');
  }
  if (request.method != 'POST') return false;
  if (request.url.path.endsWith('/refresh')) return true;
  final type = request.headers['content-type'] ?? '';
  if (!type.startsWith('application/x-www-form-urlencoded')) return false;
  return Uri.splitQueryString(request.body)['grant_type'] == 'refresh_token';
}
