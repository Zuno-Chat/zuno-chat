import 'dart:async';

import 'package:http/http.dart' as http;

typedef FakeHttpHandler = Future<http.Response> Function(http.Request request);

class FakeHttpClient extends http.BaseClient {
  FakeHttpClient(this._handler);

  final FakeHttpHandler _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bodyBytes = await request.finalize().toBytes();
    final received = http.Request(request.method, request.url)
      ..persistentConnection = request.persistentConnection
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..headers.addAll(request.headers)
      ..bodyBytes = bodyBytes
      ..finalize();
    final response = await _handler(received);
    return http.StreamedResponse(
      fakeTimeBody(response.bodyBytes),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }
}

http.ByteStream fakeTimeBody(List<int> bytes) {
  final body = StreamController<List<int>>(onCancel: () => Future<void>.value())
    ..add(bytes)
    ..close();
  return http.ByteStream(body.stream);
}
