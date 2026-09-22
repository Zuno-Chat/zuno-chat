import 'package:matrix/matrix.dart';

Uri? gatewayOrigin(Client client, List<String> pathSegments) {
  final homeserver = client.homeserver;
  if (homeserver == null) return null;
  return Uri(
    scheme: homeserver.scheme,
    host: homeserver.host,
    port: homeserver.hasPort ? homeserver.port : null,
    pathSegments: pathSegments,
  );
}
