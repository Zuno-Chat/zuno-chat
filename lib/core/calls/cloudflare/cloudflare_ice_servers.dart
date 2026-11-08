import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import '../../errors/caught_errors.dart';
import '../../matrix/http/bearer_authorization.dart';
import '../module/calls_module.dart';
import 'cloudflare_routes.dart';
import 'cloudflare_turn_client.dart';

const _turnBudget = Duration(seconds: 5);

Future<List<Map<String, Object?>>> resolveCloudflareIceServers(
  Client client, {
  http.Client? httpClient,
}) async {
  try {
    return await fetchCloudflareIceServers(
      credentialsUri: turnCredentialsUri(client),
      authorization: () => bearerAuthorization(client),
      httpClient: httpClient,
    ).timeout(_turnBudget);
  } catch (e, s) {
    if (!isExpectedCallsFailure(e)) reportCaught('mint TURN credentials', e, s);
    return const [];
  }
}
