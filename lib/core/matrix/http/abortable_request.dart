import 'package:http/http.dart' as http;
import 'package:zuno_http/zuno_http.dart' show DeadlineRequest;

DeadlineRequest abortableCopy(
  http.Request request,
  Future<void> abortTrigger, {
  Duration? thinkTime,
}) =>
    DeadlineRequest(
        request.method,
        request.url,
        abortTrigger: abortTrigger,
        thinkTime:
            thinkTime ??
            switch (request) {
              DeadlineRequest(:final thinkTime) => thinkTime,
              _ => null,
            },
      )
      ..headers.addAll(request.headers)
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection
      ..bodyBytes = request.bodyBytes;
