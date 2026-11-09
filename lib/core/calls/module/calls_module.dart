import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno_http/zuno_http.dart';

import '../../errors/retry_backoff.dart';
import '../../matrix/http/bearer_authorization.dart';
import '../../matrix/http/typed_server_answers.dart';
import '../../network/app_http_client.dart';
import '../models/sfu_failures.dart';

const _modulePath = ['_synapse', 'client', 'zuno', 'calls'];

Uri callsModuleUri(Client client, List<String> segments) {
  final homeserver = client.homeserver;
  if (homeserver == null) {
    throw StateError(
      'No homeserver set — the calls module is served by it. '
      'A server check or sign-in must have run first.',
    );
  }
  return homeserver.resolveUri(
    Uri(pathSegments: [..._modulePath, ...segments]),
  );
}

final _errorCodePattern = RegExp(r'^[A-Za-z0-9_.]{1,64}$');

Object? _bodyJson(http.Response response) {
  try {
    return jsonDecode(response.body);
  } on FormatException {
    return null;
  }
}

String? moduleErrorCode(Object? json) {
  if (json is! Map) return null;
  final code = json['errorCode'] ?? json['errcode'];
  return code is String && _errorCodePattern.hasMatch(code) ? code : null;
}

class CallFullException implements Exception {
  const CallFullException(this.maxParticipants);

  final int maxParticipants;

  @override
  String toString() => 'CallFullException: $maxParticipants people at most';
}

const callRemovedErrorCode = 'IM.ZUNO.CALL_REMOVED';

class CallRemovedException implements Exception {
  const CallRemovedException();

  @override
  String toString() => 'CallRemovedException: removed from this call';
}

Exception? moduleRefusalOf(http.Response response) {
  if (response.statusCode != 403) return null;
  return switch (_bodyJson(response)) {
    {
      'errcode': 'IM.ZUNO.CALL_FULL',
      'max_participants': final int maxParticipants,
    }
        when maxParticipants >= 1 =>
      CallFullException(maxParticipants),
    {'errcode': callRemovedErrorCode} => const CallRemovedException(),
    _ => null,
  };
}

class CallsModuleException implements Exception {
  CallsModuleException(this.message, {this.statusCode, this.retryAfter});

  final String message;
  final int? statusCode;
  final Duration? retryAfter;

  @override
  String toString() => 'CallsModuleException: $message';
}

class CallsRouteGone implements Exception {
  const CallsRouteGone(this.route);

  final String route;

  @override
  String toString() => 'CallsRouteGone: the module does not serve $route';
}

bool isRouteGone(http.Response response) =>
    response.statusCode == 404 &&
    moduleErrorCode(_bodyJson(response)) == 'M_UNRECOGNIZED';

bool isExpectedCallsFailure(Object error) => switch (error) {
  CallsRouteGone() || SfuUnreachable() => true,
  CallsModuleException(:final statusCode?) =>
    statusCode >= 500 || statusCode == 429,
  _ => isExpectedServerFailure(error),
};

const _requestDeadline = Duration(seconds: 15);
const _sendableMethods = {'GET', 'POST', 'PUT'};
const _retryBaseDelay = Duration(milliseconds: 150);
const _retryMaxDelay = Duration(milliseconds: 1500);

Future<Map<String, dynamic>> sendToCallsModule({
  required String method,
  required Uri uri,
  required String request,
  required Future<String> Function() authorization,
  Map<String, Object?>? body,
  bool resendable = false,
  http.Client? httpClient,
}) async {
  final client = httpClient ?? appHttpClient(HttpClientKind.service);
  final encoded = body == null ? null : jsonEncode(body);

  Future<Map<String, dynamic>> sendOnce() async {
    final headers = {
      'Authorization': await authorization(),
      if (encoded != null) 'Content-Type': 'application/json',
    };
    if (!_sendableMethods.contains(method)) {
      throw ArgumentError('Unsupported method $method');
    }
    final outgoing = DeadlineRequest(method, uri, thinkTime: _requestDeadline)
      ..headers.addAll(headers);
    if (encoded != null) outgoing.body = encoded;
    final response = await http.Response.fromStream(
      await client.send(outgoing),
    );
    if (moduleRefusalOf(response) case final refusal?) throw refusal;
    if (isRouteGone(response)) throw CallsRouteGone(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CallsModuleException(
        moduleFailure(response, request),
        statusCode: response.statusCode,
        retryAfter: retryAfterOf(response),
      );
    }
    final text = response.body;
    return text.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(text) as Map<String, dynamic>;
  }

  try {
    return await retryWithBackoff(
      sendOnce,
      label: request,
      baseDelay: _retryBaseDelay,
      maxDelay: _retryMaxDelay,
      retryIf: (error) =>
          (resendable && _droppedInTransit(error)) ||
          (error is CallsModuleException && error.statusCode == 429),
      retryAfter: (error) =>
          error is CallsModuleException ? error.retryAfter : null,
    );
  } finally {
    if (httpClient == null) client.close();
  }
}

bool _droppedInTransit(Object error) =>
    error is http.ClientException &&
    !(error is NativeHttpException && error.ranOutOfTime);

Future<void> requestCallRemoval(
  Client client, {
  required String roomId,
  required String callId,
  required String userId,
  http.Client? httpClient,
}) => sendToCallsModule(
  method: 'POST',
  uri: callsModuleUri(client, const [
    'remove',
  ]).replace(queryParameters: {'room_id': roomId, 'call_id': callId}),
  request: 'POST /remove',
  authorization: () => bearerAuthorization(client),
  body: {'user_id': userId},
  resendable: true,
  httpClient: httpClient,
);

String moduleFailure(http.Response response, String request) {
  final failure = 'HTTP ${response.statusCode} from $request';
  final code = moduleErrorCode(_bodyJson(response));
  return code == null ? failure : '$failure: $code';
}

Duration? retryAfterOf(http.Response response) {
  if (response.statusCode != 429) return null;
  final json = _bodyJson(response);
  final ms = json is Map ? json['retry_after_ms'] : null;
  return ms is int && ms > 0 ? Duration(milliseconds: ms) : null;
}
