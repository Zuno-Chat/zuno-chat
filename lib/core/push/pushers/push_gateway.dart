const matrixPushGatewayPath = '/_matrix/push/v1/notify';

Uri? homeserverPushGatewayUri(Uri? homeserver) {
  if (homeserver == null) return null;
  return Uri(
    scheme: 'https',
    host: homeserver.host,
    port: homeserver.hasPort ? homeserver.port : null,
    path: matrixPushGatewayPath,
  );
}
