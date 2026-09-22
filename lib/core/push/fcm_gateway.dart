import 'matrix_unified_push_gateway.dart' show matrixPushGatewayPath;

Uri? fcmGatewayUri(Uri? homeserver) {
  if (homeserver == null) return null;
  return Uri(
    scheme: 'https',
    host: homeserver.host,
    port: homeserver.hasPort ? homeserver.port : null,
    path: matrixPushGatewayPath,
  );
}
