import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:zuno_http/zuno_http.dart';

import '../errors/caught_errors.dart';
import 'app_http_overrides.dart';

enum HttpClientKind {
  matrix(HttpDeadlines()),
  service(
    HttpDeadlines(
      thinkTime: Duration(seconds: 30),
      idle: Duration(seconds: 30),
    ),
  );

  const HttpClientKind(this.deadlines);

  final HttpDeadlines deadlines;
}

http.Client appHttpClient(HttpClientKind kind) => appHttpClientFactory(kind);

Future<ZunoWebSocket> appWebSocket(Uri url, Map<String, String> headers) =>
    appWebSocketFactory(url, headers);

@visibleForTesting
http.Client Function(HttpClientKind kind) appHttpClientFactory =
    nativeHttpClient;

@visibleForTesting
Future<ZunoWebSocket> Function(Uri url, Map<String, String> headers)
appWebSocketFactory = (url, headers) =>
    ZunoWebSocket.connect(url, headers: headers, userAgent: networkUserAgent);

Future<void>? _engineReady;

@visibleForTesting
http.Client nativeHttpClient(HttpClientKind kind, {NativeHttp? native}) {
  final engine = native ?? ChannelNativeHttp.instance;
  _engineReady ??= engine.ready().catchError(
    (Object error, StackTrace stack) =>
        reportCaught('start the network engine', error, stack),
  );
  return ZunoHttpClient(
    userAgent: networkUserAgent,
    deadlines: kind.deadlines,
    native: engine,
  );
}

@visibleForTesting
void forgetNetworkEngineReadyForTest() => _engineReady = null;
