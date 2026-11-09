import 'dart:collection';

Map<String, String> headerMap(Map<String, String> from) =>
    LinkedHashMap<String, String>(
      equals: (a, b) => a.toLowerCase() == b.toLowerCase(),
      hashCode: (key) => key.toLowerCase().hashCode,
    )..addAll(from);

Map<String, String> withUserAgent(
  Map<String, String> headers,
  String userAgent,
) => headerMap(headers)..putIfAbsent('user-agent', () => userAgent);
