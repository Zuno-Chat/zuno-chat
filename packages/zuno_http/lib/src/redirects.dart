const _redirectStatuses = {301, 302, 303, 307, 308};

const _sensitiveHeaders = {
  'authorization',
  'www-authenticate',
  'proxy-authorization',
  'proxy-authenticate',
  'cookie',
  'cookie2',
};

bool followsRedirect(String method, int status) => switch (method) {
  'GET' || 'HEAD' => _redirectStatuses.contains(status),
  'POST' => status == 303,
  _ => false,
};

Map<String, String> redirectHeaders(
  Uri from,
  Uri to,
  Map<String, String> headers,
) {
  final sameOrigin =
      from.isScheme(to.scheme) && from.host == to.host && from.port == to.port;
  return {
    for (final MapEntry(:key, :value) in headers.entries)
      if (sameOrigin || !_sensitiveHeaders.contains(key.toLowerCase()))
        key: value,
  };
}
