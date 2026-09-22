import 'package:sentry_flutter/sentry_flutter.dart';

const _redacted = '[redacted]';

final _bearerPattern = RegExp(
  r'\b(bearer)\s+[A-Za-z0-9._~+/=-]+',
  caseSensitive: false,
);

final _tokenParameterPattern = RegExp(
  r'\b((?:access|refresh|id)_token)=[^&\s"]+',
  caseSensitive: false,
);

final _sigilPattern = RegExp(r'([@!#$])[A-Za-z0-9._=+/~-]+:[A-Za-z0-9.-]+');

final _eventIdPattern = RegExp(r'\$[A-Za-z0-9_-]{43}(?![A-Za-z0-9_-])');

String? scrubText(String? input) {
  if (input == null || input.isEmpty) return input;
  return input
      .replaceAllMapped(_bearerPattern, (m) => '${m[1]} $_redacted')
      .replaceAllMapped(_tokenParameterPattern, (m) => '${m[1]}=$_redacted')
      .replaceAllMapped(_sigilPattern, (m) => '${m[1]}$_redacted')
      .replaceAll(_eventIdPattern, '\$$_redacted');
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
    exception.value = scrubText(exception.value);
  }

  for (final crumb in event.breadcrumbs ?? const <Breadcrumb>[]) {
    scrubBreadcrumb(crumb);
  }

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
  crumb.message = scrubText(crumb.message);
  crumb.data = crumb.data?.map(
    (key, value) => MapEntry(key, value is String ? scrubText(value) : value),
  );
  return crumb;
}
