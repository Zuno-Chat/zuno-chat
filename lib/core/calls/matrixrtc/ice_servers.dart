import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import '../../matrix/bearer_authorization.dart';
import '../cloudflare/calls_module.dart';
import '../cloudflare/cloudflare_turn_client.dart';

const _turnBudget = Duration(seconds: 5);

Future<List<Map<String, Object?>>> resolveIceServers(
  Client client, {
  http.Client? httpClient,
}) async {
  try {
    return await fetchCloudflareIceServers(
      credentialsUri: turnCredentialsUri(client),
      authorization: () => bearerAuthorization(client),
      httpClient: httpClient,
    ).timeout(_turnBudget);
  } catch (e) {
    debugPrint('[ice_servers] TURN credential mint failed: $e');
    return const [];
  }
}
