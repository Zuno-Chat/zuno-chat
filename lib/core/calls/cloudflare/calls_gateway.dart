import 'package:matrix/matrix.dart';

Uri callsGatewayBaseUri(Client client) => _hostUri(client, 'calls');

Uri turnCredentialsUri(Client client) =>
    _hostUri(client, 'turn').replace(pathSegments: ['turn', 'credentials']);

Uri _hostUri(Client client, String segment) {
  final homeserver = client.homeserver;
  if (homeserver == null) {
    throw StateError(
      'No homeserver set — the calls gateway is derived from it. '
      'checkHomeserver()/login must have run first.',
    );
  }
  return Uri(
    scheme: homeserver.scheme,
    host: homeserver.host,
    port: homeserver.hasPort ? homeserver.port : null,
    pathSegments: [segment],
  );
}
