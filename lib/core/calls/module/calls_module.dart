import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import '../../errors/retry_backoff.dart';
import '../../matrix/bearer_authorization.dart';

const _modulePath = ['_synapse', 'client', 'zuno', 'calls'];

Uri callsModuleUri(Client client, List<String> segments) {
  final homeserver = client.homeserver;
  if (homeserver == null) {
    throw StateError(
      'No homeserver set — the calls module is served by it. '
      'checkHomeserver()/login must have run first.',
    );
  }
  return homeserver.resolveUri(
    Uri(pathSegments: [..._modulePath, ...segments]),
  );
}

final _errorCodePattern = RegExp(r'^[A-Za-z0-9_.]{1,64}$');

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
  try {
    return switch (jsonDecode(response.body)) {
      {
        'errcode': 'IM.ZUNO.CALL_FULL',
        'max_participants': final int maxParticipants,
      }
          when maxParticipants >= 1 =>
        CallFullException(maxParticipants),
      {'errcode': callRemovedErrorCode} => const CallRemovedException(),
      _ => null,
    };
  } on FormatException {
    return null;
  }
}

class CallsModuleException implements Exception {
  CallsModuleException(this.message, {this.statusCode, this.retryAfter});

  final String message;
  final int? statusCode;
  final Duration? retryAfter;

  @override
  String toString() => 'CallsModuleException: $message';
}

const _requestDeadline = Duration(seconds: 15);
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
  final client = httpClient ?? http.Client();
  final encoded = body == null ? null : jsonEncode(body);

  Future<Map<String, dynamic>> sendOnce() async {
    final headers = {
      'Authorization': await authorization(),
      if (encoded != null) 'Content-Type': 'application/json',
    };
    final response = await switch (method) {
      'POST' => client.post(uri, headers: headers, body: encoded),
      'PUT' => client.put(uri, headers: headers, body: encoded),
      _ => throw ArgumentError('Unsupported method $method'),
    }.timeout(_requestDeadline);
    if (moduleRefusalOf(response) case final refusal?) throw refusal;
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
          (resendable &&
              (error is SocketException || error is http.ClientException)) ||
          (error is CallsModuleException && error.statusCode == 429),
      retryAfter: (error) =>
          error is CallsModuleException ? error.retryAfter : null,
    );
  } finally {
    if (httpClient == null) client.close();
  }
}

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
  final Object? json;
  try {
    json = jsonDecode(response.body);
  } on FormatException {
    return failure;
  }
  final code = moduleErrorCode(json);
  return code == null ? failure : '$failure: $code';
}

Duration? retryAfterOf(http.Response response) {
  if (response.statusCode != 429) return null;
  try {
    final json = jsonDecode(response.body);
    final ms = json is Map ? json['retry_after_ms'] : null;
    return ms is int && ms > 0 ? Duration(milliseconds: ms) : null;
  } on FormatException {
    return null;
  }
}
