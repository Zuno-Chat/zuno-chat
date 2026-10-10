import 'package:sentry_flutter/sentry_flutter.dart';

const _redacted = '[redacted]';

final _jsonObjectPattern = RegExp(r'\{.*\}', dotAll: true);

final _urlHostPattern = RegExp(
  r'\b([a-z][a-z0-9+.-]*://)[^/\s?#"\x27]+',
  caseSensitive: false,
);

final _geoPattern = RegExp(r'\bgeo:[^\s"\x27]+', caseSensitive: false);

final _filePathPattern = RegExp(
  r'(?<![\w.-])/(?:private/)?(?:var|data|storage|sdcard|mnt|tmp|Users)/'
  r'[^\x27"()\n]*?(?=: |[\x27"()\n]|$)',
);

final _quotedNamePattern = RegExp('“[^”]*”');

final _bearerPattern = RegExp(
  r'\b(bearer)\s+[A-Za-z0-9._~+/=-]+',
  caseSensitive: false,
);

final _tokenParameterPattern = RegExp(
  r'\b((?:access|refresh|id)_token)=[^&\s"]+',
  caseSensitive: false,
);

final _sigilPattern = RegExp(r'([@!#$])[A-Za-z0-9._=+/~-]+:[A-Za-z0-9.-]+');

final _hashIdPattern = RegExp(r'([$!])[A-Za-z0-9_-]{43}(?![A-Za-z0-9_-])');

String? scrubText(String? input) {
  if (input == null || input.isEmpty) return input;
  return input
      .replaceAll(_jsonObjectPattern, '{$_redacted}')
      .replaceAllMapped(_urlHostPattern, (m) => '${m[1]}$_redacted')
      .replaceAll(_geoPattern, 'geo:$_redacted')
      .replaceAll(_filePathPattern, '[path]')
      .replaceAll(_quotedNamePattern, '“$_redacted”')
      .replaceAllMapped(_bearerPattern, (m) => '${m[1]} $_redacted')
      .replaceAllMapped(_tokenParameterPattern, (m) => '${m[1]}=$_redacted')
      .replaceAllMapped(_sigilPattern, (m) => '${m[1]}$_redacted')
      .replaceAllMapped(_hashIdPattern, (m) => '${m[1]}$_redacted');
}

SentryEvent scrubEvent(SentryEvent event) {
  final message = event.message;
  if (message != null) {
    message.formatted = scrubText(message.formatted)!;
    message.template = scrubText(message.template);
    message.params = message.params
        ?.map((p) => p is String ? scrubText(p) : p)
        .toList();
  }

  for (final exception in event.exceptions ?? const <SentryException>[]) {
    final value = exception.type == 'FormatException'
        ? exception.value?.split('\n').first
        : exception.value;
    exception.value = scrubText(value);
    final mechanism = exception.mechanism;
    if (mechanism != null) {
      mechanism.data = mechanism.data.map(
        (key, value) =>
            MapEntry(key, value is String ? scrubText(value) : value),
      );
    }
  }

  for (final crumb in event.breadcrumbs ?? const <Breadcrumb>[]) {
    scrubBreadcrumb(crumb);
  }

  event.tags = event.tags?.map(
    (key, value) => MapEntry(key, scrubText(value)!),
  );
  event.fingerprint = event.fingerprint
      ?.map((part) => scrubText(part)!)
      .toList();

  final request = event.request;
  if (request != null) {
    request.url = scrubText(request.url);
    request.queryString = scrubText(request.queryString);
    request.fragment = scrubText(request.fragment);
    request.cookies = null;
    request.headers = request.headers.map(
      (key, value) => MapEntry(key, scrubText(value)!),
    );
  }

  return event;
}

Breadcrumb scrubBreadcrumb(Breadcrumb crumb) {
  crumb.message = scrubText(crumb.message?.split('\n').first);
  crumb.data = crumb.data?.map(
    (key, value) => MapEntry(key, value is String ? scrubText(value) : value),
  );
  return crumb;
}
