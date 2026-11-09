import 'package:http/http.dart' as http;

enum HttpFailureKind {
  offline,
  dns,
  connect,
  connectTimedOut,
  tls,
  timedOut,
  connectionLost,
  protocol,
  cancelled,
}

class NativeHttpException extends http.ClientException {
  NativeHttpException(this.kind, String detail, [Uri? uri])
    : super(detail, uri);

  final HttpFailureKind kind;

  bool get ranOutOfTime =>
      kind == HttpFailureKind.connectTimedOut ||
      kind == HttpFailureKind.timedOut;

  @override
  String toString() =>
      'NativeHttpException(${kind.name}): $message'
      '${uri == null ? '' : ', uri=$uri'}';
}

class NativeEngineUnavailable implements Exception {
  const NativeEngineUnavailable(this.detail);

  final String detail;

  @override
  String toString() => 'NativeEngineUnavailable: $detail';
}

class WebSocketUpgradeRefused implements Exception {
  const WebSocketUpgradeRefused(this.status);

  final int status;

  @override
  String toString() => 'WebSocketUpgradeRefused: $status';
}
