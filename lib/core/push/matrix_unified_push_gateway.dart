import 'dart:convert';

import 'package:http/http.dart' as http;

final fallbackMatrixGatewayUrl = Uri.parse(
  'https://matrix.gateway.unifiedpush.org/_matrix/push/v1/notify',
);

const matrixPushGatewayPath = '/_matrix/push/v1/notify';

Future<Uri> resolveMatrixGatewayUrl(
  Uri endpointUrl, {
  required http.Client httpClient,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final discoveryUrl = Uri(
    scheme: endpointUrl.scheme,
    host: endpointUrl.host,
    port: endpointUrl.hasPort ? endpointUrl.port : null,
    path: matrixPushGatewayPath,
  );
  try {
    final response = await httpClient.get(discoveryUrl).timeout(timeout);
    if (response.statusCode != 200) return fallbackMatrixGatewayUrl;
    final body = jsonDecode(response.body);
    final gateway = body is Map ? body['unifiedpush'] : null;
    if (gateway is Map && gateway['gateway'] == 'matrix') return discoveryUrl;
  } catch (_) {}
  return fallbackMatrixGatewayUrl;
}
