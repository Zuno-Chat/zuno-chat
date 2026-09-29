import 'package:http/http.dart' as http;

class FreshTokenHttpClient extends http.BaseClient {
  FreshTokenHttpClient(
    this._inner, {
    required this._accessToken,
    required this._ensureFresh,
  });

  final http.Client _inner;
  final String? Function() _accessToken;
  final Future<void> Function() _ensureFresh;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final token = _accessToken();
    if (token != null && request.headers['authorization'] == 'Bearer $token') {
      await _ensureFresh();
      final fresh = _accessToken();
      if (fresh != null && fresh != token) {
        request.headers['authorization'] = 'Bearer $fresh';
      }
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
