import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:zuno_http/zuno_http.dart';

typedef FakeHttpHandler = Future<http.Response> Function(http.Request request);

class FakeHttpClient extends http.BaseClient {
  FakeHttpClient(this._handler);

  final FakeHttpHandler _handler;
  var closed = false;

  @override
  void close() => closed = true;

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
    final answer = _handler(received);
    final response = await switch (request) {
      DeadlineRequest(:final thinkTime?) => answer.timeout(
        thinkTime,
        onTimeout: () => throw NativeHttpException(
          HttpFailureKind.timedOut,
          'No answer within ${thinkTime.inSeconds} s',
          request.url,
        ),
      ),
      _ => answer,
    };
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

class RecordingHttpClient extends http.BaseClient {
  final received = <http.BaseRequest>[];

  http.BaseRequest get last => received.last;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    received.add(request);
    return http.StreamedResponse(fakeTimeBody(const []), 200);
  }
}
