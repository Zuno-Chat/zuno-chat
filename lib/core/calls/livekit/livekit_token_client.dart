import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import '../../matrix/http/bearer_authorization.dart';
import '../media/call_connection.dart';
import '../module/calls_module.dart';

typedef LiveKitGrant = ({Uri url, String token});

const _request = 'POST /livekit/token';

Future<LiveKitGrant> fetchLiveKitGrant(
  Client client,
  CallSpec spec, {
  http.Client? httpClient,
}) async {
  final answer = await sendToCallsModule(
    method: 'POST',
    uri: callsModuleUri(client, const ['livekit', 'token']).replace(
      queryParameters: {'room_id': spec.roomId, 'call_id': spec.callId},
    ),
    request: _request,
    authorization: () => bearerAuthorization(client),
    resendable: true,
    httpClient: httpClient,
  );
  final url = switch (answer['url']) {
    final String text => Uri.tryParse(text),
    _ => null,
  };
  final token = answer['token'];
  if (url == null || url.scheme != 'wss' || url.host.isEmpty) {
    throw CallsModuleException('$_request answered without a wss url');
  }
  if (token is! String || token.isEmpty) {
    throw CallsModuleException('$_request answered without a token');
  }
  return (url: url, token: token);
}
