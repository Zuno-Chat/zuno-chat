import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import '../cloudflare/calls_gateway.dart';
import '../cloudflare/calls_gateway_credentials.dart';
import '../cloudflare/cloudflare_turn_client.dart';

Future<List<Map<String, Object?>>> resolveIceServers(
  Client client, {
  required GatewayAuthorizationProvider authorizationProvider,
  http.Client? httpClient,
}) async {
  try {
    return await fetchCloudflareIceServers(
      credentialsUri: turnCredentialsUri(client),
      authorizationProvider: authorizationProvider,
      httpClient: httpClient,
    );
  } catch (e) {
    debugPrint('[ice_servers] TURN credential mint failed: $e');
    return const [];
  }
}
