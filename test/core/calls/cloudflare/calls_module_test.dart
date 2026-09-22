import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:zuno/core/calls/cloudflare/calls_module.dart';

import '../../../helpers/fake_matrix.dart';

void main() {
  const base = '/_synapse/client/zuno/calls/cloudflare';

  group('module URIs', () {
    test('the Cloudflare backend and TURN mint hang off the homeserver', () {
      final client = buildTestClient()
        ..homeserver = Uri.parse('https://example.org');

      expect(
        cloudflareCallsBaseUri(client).toString(),
        'https://example.org$base',
      );
      expect(
        turnCredentialsUri(client).toString(),
        'https://example.org$base/turn/credentials',
      );
    });

    test('a non-default port is carried through', () {
      final client = buildTestClient()
        ..homeserver = Uri.parse('https://example.org:8448');

      expect(
        cloudflareCallsBaseUri(client).toString(),
        'https://example.org:8448$base',
      );
    });

    test('a path prefix resolves exactly as the SDK resolves /_matrix', () {
      final bare = buildTestClient()
        ..homeserver = Uri.parse('https://example.org/matrix');
      final slashed = buildTestClient()
        ..homeserver = Uri.parse('https://example.org/matrix/');

      expect(
        cloudflareCallsBaseUri(bare).toString(),
        'https://example.org$base',
      );
      expect(
        cloudflareCallsBaseUri(slashed).toString(),
        'https://example.org/matrix$base',
      );
    });

    test('throws rather than guessing when no homeserver is set', () {
      expect(() => cloudflareCallsBaseUri(buildTestClient()), throwsStateError);
      expect(() => turnCredentialsUri(buildTestClient()), throwsStateError);
    });
  });

  group('retryAfterOf', () {
    test('reads retry_after_ms from a 429', () {
      final response = http.Response(
        '{"errcode":"M_LIMIT_EXCEEDED","retry_after_ms":250}',
        429,
      );

      expect(retryAfterOf(response), const Duration(milliseconds: 250));
    });

    test('is null for a 429 without a usable retry_after_ms', () {
      expect(retryAfterOf(http.Response('{"errcode":"X"}', 429)), isNull);
      expect(retryAfterOf(http.Response('{"retry_after_ms":0}', 429)), isNull);
      expect(
        retryAfterOf(http.Response('{"retry_after_ms":"1"}', 429)),
        isNull,
      );
      expect(retryAfterOf(http.Response('not json', 429)), isNull);
    });

    test('is null for any other status', () {
      expect(
        retryAfterOf(http.Response('{"retry_after_ms":250}', 503)),
        isNull,
      );
    });
  });
}
