import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

const _modulePath = ['_synapse', 'client', 'zuno', 'calls', 'cloudflare'];

Uri cloudflareCallsBaseUri(Client client) => _moduleUri(client, const []);

Uri turnCredentialsUri(Client client) =>
    _moduleUri(client, const ['turn', 'credentials']);

Uri _moduleUri(Client client, List<String> segments) {
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

final _errorCodePattern = RegExp(r'^[A-Za-z0-9_]{1,64}$');

String? moduleErrorCode(Object? json) {
  if (json is! Map) return null;
  final code = json['errorCode'] ?? json['errcode'];
  return code is String && _errorCodePattern.hasMatch(code) ? code : null;
}

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
