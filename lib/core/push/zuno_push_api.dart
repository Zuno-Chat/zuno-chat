import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import '../matrix/bearer_authorization.dart';
import 'zuno_push_replies.dart';

export 'zuno_push_replies.dart';

const zunoPushPath = ['_synapse', 'client', 'zuno', 'push', 'v1'];

Uri zunoPushUri(Uri homeserver, List<String> segments) =>
    homeserver.resolveUri(Uri(pathSegments: [...zunoPushPath, ...segments]));

enum ZunoPushFailureKind {
  route,
  network,
  noSession,
  malformed,
  badRequest,
  unauthorized,
  badCredential,
  rateLimited,
  disabled,
  notPusherInstance,
  unexpected,
}

sealed class ZunoPushResult<T> {
  const ZunoPushResult();
}

final class ZunoPushOk<T> extends ZunoPushResult<T> {
  const ZunoPushOk(this.value, {required this.serverTs});

  final T value;
  final int serverTs;
}

final class ZunoPushFailure<T> extends ZunoPushResult<T> {
  const ZunoPushFailure(
    this.kind, {
    this.status,
    this.errcode,
    this.error,
    this.retryAfter,
  });

  final ZunoPushFailureKind kind;
  final int? status;
  final String? errcode;
  final String? error;
  final Duration? retryAfter;
}

bool _fromModule(http.BaseResponse response) => response.headers.entries.any(
  (header) =>
      header.key.toLowerCase() == 'x-zuno-push' && header.value.trim() == '1',
);

ZunoPushFailureKind _failureKind(int status, String? errcode) => switch ((
  status,
  errcode,
)) {
  (400, 'M_INVALID_PARAM' || 'M_NOT_JSON') => ZunoPushFailureKind.badRequest,
  (401, 'M_MISSING_TOKEN' || 'M_UNKNOWN_TOKEN') =>
    ZunoPushFailureKind.unauthorized,
  (401, 'IM.ZUNO.BAD_CREDENTIAL') => ZunoPushFailureKind.badCredential,
  (429, 'M_LIMIT_EXCEEDED') => ZunoPushFailureKind.rateLimited,
  (503, 'IM.ZUNO.PUSH_DISABLED') => ZunoPushFailureKind.disabled,
  (503, 'IM.ZUNO.NOT_PUSHER_INSTANCE') => ZunoPushFailureKind.notPusherInstance,
  _ => ZunoPushFailureKind.unexpected,
};

ZunoPushResult<T> zunoPushResultOf<T>(
  http.Response response,
  T Function(Map<String, Object?> json) parse,
) {
  final status = response.statusCode;
  if (!_fromModule(response)) {
    return ZunoPushFailure(ZunoPushFailureKind.route, status: status);
  }
  ZunoPushFailure<T> malformed(String error) => ZunoPushFailure(
    ZunoPushFailureKind.malformed,
    status: status,
    error: error,
  );
  final Map<String, Object?> json;
  try {
    json = zunoPushObject(jsonDecode(utf8.decode(response.bodyBytes)), 'body');
  } on FormatException catch (e) {
    return malformed(e.message);
  }
  if (status != 200) {
    final errcode = json['errcode'] is String
        ? json['errcode'] as String
        : null;
    final kind = _failureKind(status, errcode);
    final retryAfterMs = json['retry_after_ms'];
    return ZunoPushFailure(
      kind,
      status: status,
      errcode: errcode,
      error: json['error'] is String ? json['error'] as String : null,
      retryAfter:
          kind == ZunoPushFailureKind.rateLimited &&
              retryAfterMs is int &&
              retryAfterMs > 0
          ? Duration(milliseconds: retryAfterMs)
          : null,
    );
  }
  final serverTs = json['server_ts'];
  if (serverTs is! int) return malformed('server_ts is not an integer');
  try {
    return ZunoPushOk(parse(json), serverTs: serverTs);
  } on FormatException catch (e) {
    return malformed(e.message);
  }
}

void _nothing(Map<String, Object?> json) {}

class ZunoPushApi {
  ZunoPushApi({
    required this.homeserver,
    required this.bearer,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  }) : _http = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  factory ZunoPushApi.forClient(Client client, {http.Client? httpClient}) {
    final homeserver = client.homeserver;
    if (homeserver == null) {
      throw StateError('No homeserver set; zuno_push is served by it.');
    }
    return ZunoPushApi(
      homeserver: homeserver,
      bearer: () => bearerAuthorization(client),
      httpClient: httpClient,
    );
  }

  final Uri homeserver;
  final Future<String> Function() bearer;
  final Duration timeout;
  final http.Client _http;
  final bool _ownsHttpClient;

  Future<ZunoPushResult<int>> putVoip({
    required String appId,
    required String pushkey,
    required int kid,
    required String key,
  }) => _send(
    'PUT',
    const ['voip'],
    body: {'app_id': appId, 'pushkey': pushkey, 'kid': kid, 'key': key},
    parse: (json) {
      final acked = json['kid'];
      if (acked is! int) throw const FormatException('kid is not an integer');
      return acked;
    },
  );

  Future<ZunoPushResult<void>> deleteVoip() =>
      _send('DELETE', const ['voip'], parse: _nothing);

  Future<ZunoPushResult<void>> deleteDevice() =>
      _send('DELETE', const ['device'], parse: _nothing);

  Future<ZunoPushResult<PushHealth>> health() =>
      _send('GET', const ['health'], parse: PushHealth.fromJson);

  Future<ZunoPushResult<String>> sendTestAlert() => _send(
    'POST',
    const ['test'],
    body: const {},
    parse: (json) {
      final eventId = json['event_id'];
      if (eventId is! String) {
        throw const FormatException('event_id is not a string');
      }
      return eventId;
    },
  );

  Future<ZunoPushResult<NseCredentialGrant>> mintNseCredential() => _send(
    'POST',
    const ['nse', 'credential'],
    body: const {},
    parse: NseCredentialGrant.fromJson,
  );

  void close() {
    if (_ownsHttpClient) _http.close();
  }

  Future<ZunoPushResult<T>> _send<T>(
    String method,
    List<String> path, {
    Map<String, Object?>? body,
    required T Function(Map<String, Object?> json) parse,
  }) async {
    final String authorization;
    try {
      authorization = await bearer();
    } on StateError catch (e) {
      return ZunoPushFailure(ZunoPushFailureKind.noSession, error: e.message);
    } on MatrixException catch (e) {
      return ZunoPushFailure(
        ZunoPushFailureKind.unauthorized,
        errcode: e.errcode,
        error: e.errorMessage,
      );
    } catch (e) {
      return ZunoPushFailure(ZunoPushFailureKind.network, error: '$e');
    }
    final request = http.Request(method, zunoPushUri(homeserver, path))
      ..headers['Authorization'] = authorization;
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await _http
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
    } catch (e) {
      return ZunoPushFailure(ZunoPushFailureKind.network, error: '$e');
    }
    return zunoPushResultOf(response, parse);
  }
}
