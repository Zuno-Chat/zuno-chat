import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:zuno/core/errors/crash_scrubber.dart';

const _eventIdV3 = r'$Rqnc-F-dvnEYJTyHq_iKxU2bZ1CI92-kFZ2qJVYTvvA';

void main() {
  group('scrubText', () {
    test('redacts a user ID but keeps the sigil', () {
      expect(
        scrubText('failed to invite @alice:zuno.chat'),
        'failed to invite @[redacted]',
      );
    });

    test('redacts room IDs, aliases and v1 event IDs', () {
      expect(
        scrubText('!abcdef:zuno.chat #family:zuno.chat \$xyz:zuno.chat'),
        '![redacted] #[redacted] \$[redacted]',
      );
    });

    test('redacts a v3 event ID', () {
      expect(
        scrubText('event $_eventIdV3 failed'),
        'event \$[redacted] failed',
      );
    });

    test('redacts an access token query parameter', () {
      expect(
        scrubText(
          'GET https://matrix.example.org/_matrix/sync?access_token=syt_abc'
          '&since=s72',
        ),
        'GET https://matrix.example.org/_matrix/sync?access_token=[redacted]'
        '&since=s72',
      );
    });

    test('redacts a bearer token', () {
      expect(
        scrubText('authorization: Bearer syt_ZXhhbXBsZQ.abc'),
        'authorization: Bearer [redacted]',
      );
    });

    test('redacts every identifier in a room path', () {
      expect(
        scrubText(
          'POST /_matrix/client/v3/rooms/!room:zuno.chat/send/m.room.message',
        ),
        'POST /_matrix/client/v3/rooms/![redacted]/send/m.room.message',
      );
    });

    test('leaves an ordinary stack trace alone', () {
      const trace =
          '#0      main (package:zuno/main.dart:12:3)\n'
          '#1      _runApp (package:zuno/main.dart:29:9)';
      expect(scrubText(trace), trace);
    });

    test('leaves annotations, clock times and plain prose alone', () {
      const text = '@override at 12:30 — SocketException: connection refused';
      expect(scrubText(text), text);
    });

    test('passes through null and empty input', () {
      expect(scrubText(null), isNull);
      expect(scrubText(''), '');
    });
  });

  group('scrubEvent', () {
    test('redacts the message, exception values and request', () {
      final event = SentryEvent(
        message: SentryMessage('sync failed for @alice:zuno.chat'),
        exceptions: [
          SentryException(
            type: 'MatrixException',
            value: 'no membership in !room:zuno.chat',
          ),
        ],
        request: SentryRequest(
          url: 'https://matrix.example.org/_matrix/client/v3/rooms/!room:zuno.chat',
          queryString: 'access_token=syt_abc',
          headers: const {'Authorization': 'Bearer syt_abc'},
        ),
      );

      final scrubbed = scrubEvent(event);

      expect(scrubbed.message?.formatted, 'sync failed for @[redacted]');
      expect(scrubbed.exceptions?.single.value, 'no membership in ![redacted]');
      expect(scrubbed.exceptions?.single.type, 'MatrixException');
      expect(
        scrubbed.request?.url,
        'https://matrix.example.org/_matrix/client/v3/rooms/![redacted]',
      );
      expect(scrubbed.request?.queryString, 'access_token=[redacted]');
      expect(scrubbed.request?.headers['Authorization'], 'Bearer [redacted]');
    });

    test('redacts breadcrumbs carried on the event', () {
      final event = SentryEvent(
        breadcrumbs: [Breadcrumb(message: 'opened !room:zuno.chat')],
      );

      expect(
        scrubEvent(event).breadcrumbs?.single.message,
        'opened ![redacted]',
      );
    });

    test('leaves an event with nothing sensitive untouched', () {
      final event = SentryEvent(
        message: SentryMessage('RangeError: index out of range'),
      );

      expect(
        scrubEvent(event).message?.formatted,
        'RangeError: index out of range',
      );
    });

    test('survives an event with no message, exceptions or request', () {
      expect(() => scrubEvent(SentryEvent()), returnsNormally);
    });
  });

  group('scrubBreadcrumb', () {
    test('redacts the message and string data values', () {
      final crumb = Breadcrumb(
        message: 'sent to !room:zuno.chat',
        category: 'matrix',
        data: {'room': '#family:zuno.chat', 'retries': 2},
      );

      final scrubbed = scrubBreadcrumb(crumb);

      expect(scrubbed.message, 'sent to ![redacted]');
      expect(scrubbed.category, 'matrix');
      expect(scrubbed.data?['room'], '#[redacted]');
      expect(scrubbed.data?['retries'], 2);
    });

    test('survives a breadcrumb with no message or data', () {
      expect(() => scrubBreadcrumb(Breadcrumb()), returnsNormally);
    });
  });
}
