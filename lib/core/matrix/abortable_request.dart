import 'package:http/http.dart' as http;

http.Request abortableCopy(http.Request request, Future<void> abortTrigger) =>
    http.AbortableRequest(
        request.method,
        request.url,
        abortTrigger: abortTrigger,
      )
      ..headers.addAll(request.headers)
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection
      ..bodyBytes = request.bodyBytes;
