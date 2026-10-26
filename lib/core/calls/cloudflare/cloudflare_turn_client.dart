import 'package:http/http.dart' as http;

import '../module/calls_module.dart';

Future<List<Map<String, Object?>>> fetchCloudflareIceServers({
  required Uri credentialsUri,
  required Future<String> Function() authorization,
  http.Client? httpClient,
}) async {
  final json = await sendToCallsModule(
    method: 'POST',
    uri: credentialsUri,
    request: 'TURN credentials',
    authorization: authorization,
    resendable: true,
    httpClient: httpClient,
  );
  final iceServers = json['iceServers'];
  if (iceServers is! List) {
    throw CallsModuleException('TURN credentials returned no ICE servers');
  }
  return iceServers
      .cast<Map<String, dynamic>>()
      .map((entry) => entry.cast<String, Object?>())
      .toList();
}
