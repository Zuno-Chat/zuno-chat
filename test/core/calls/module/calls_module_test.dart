import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/calls/cloudflare/cloudflare_routes.dart';
import 'package:zuno/core/calls/livekit/livekit_signal_client.dart';
import 'package:zuno/core/calls/module/calls_module.dart';
import 'package:zuno/core/matrix/http/typed_server_answers.dart';

import '../../../helpers/fake_http.dart';
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

  group('callsModuleUri', () {
    test('resolves segments under the calls module on the homeserver', () {
      final client = buildTestClient()
        ..homeserver = Uri.parse('https://hs.example.org');

      expect(
        callsModuleUri(client, ['livekit', 'token']).toString(),
        'https://hs.example.org/_synapse/client/zuno/calls/livekit/token',
      );
    });

    test('throws when no homeserver is set', () {
      expect(
        () => callsModuleUri(buildTestClient(), ['livekit']),
        throwsStateError,
      );
    });
  });

  group('isRouteGone', () {
    test('needs a 404 whose errcode is M_UNRECOGNIZED', () {
      expect(
        isRouteGone(http.Response('{"errcode":"M_UNRECOGNIZED"}', 404)),
        isTrue,
      );
    });

    test('a 404 with another errcode or a non-JSON body is not gone', () {
      expect(
        isRouteGone(http.Response('{"errcode":"M_NOT_FOUND"}', 404)),
        isFalse,
      );
      expect(isRouteGone(http.Response('not json', 404)), isFalse);
    });

    test('M_UNRECOGNIZED on another status is not gone', () {
      expect(
        isRouteGone(http.Response('{"errcode":"M_UNRECOGNIZED"}', 400)),
        isFalse,
      );
    });
  });

  group('isExpectedCallsFailure', () {
    test('a gone route, a module 5xx or 429 and a network failure are '
        'expected', () {
      expect(
        isExpectedCallsFailure(const CallsRouteGone('POST /livekit/token')),
        isTrue,
      );
      for (final status in [500, 503, 429]) {
        expect(
          isExpectedCallsFailure(
            CallsModuleException('HTTP $status', statusCode: status),
          ),
          isTrue,
        );
      }
      expect(isExpectedCallsFailure(const SocketException('down')), isTrue);
    });

    test('an SFU that cannot be reached is expected, and one that refuses '
        'is not', () {
      for (final kind in ['upgrade 503', 'no answer', 'SocketException']) {
        expect(isExpectedCallsFailure(LiveKitSignalUnreachable(kind)), isTrue);
      }
      expect(
        isExpectedCallsFailure(const LiveKitJoinRefused('upgrade 401')),
        isFalse,
      );
    });

    test('a client 4xx from the module is not expected', () {
      for (final status in [400, 403, 404]) {
        expect(
          isExpectedCallsFailure(
            CallsModuleException('HTTP $status', statusCode: status),
          ),
          isFalse,
        );
      }
    });

    test('a Matrix refusal is not expected, and a rate limit or a server '
        'failure is', () {
      for (final errcode in ['M_BAD_JSON', 'M_TOO_LARGE', 'M_FORBIDDEN']) {
        expect(
          isExpectedCallsFailure(
            MatrixException.fromJson({'errcode': errcode, 'error': 'x'}),
          ),
          isFalse,
        );
      }
      expect(
        isExpectedCallsFailure(
          MatrixException.fromJson({'errcode': 'M_LIMIT_EXCEEDED'}),
        ),
        isTrue,
      );
      expect(isExpectedCallsFailure(const ServerAnswerFailed(502)), isTrue);
      expect(isExpectedCallsFailure(const ServerAnswerFailed(400)), isFalse);
    });

    test('a malformed module answer is not expected', () {
      expect(
        isExpectedCallsFailure(
          CallsModuleException('POST /livekit/token answered without a token'),
        ),
        isFalse,
      );
    });

    test('a defect is not expected', () {
      expect(isExpectedCallsFailure(StateError('bug')), isFalse);
    });
  });

  group('moduleFailure', () {
    test('names the status, the request and the error code', () {
      expect(
        moduleFailure(
          http.Response(
            '{"errorCode":"session_error","errorDescription":"x"}',
            404,
          ),
          'POST /sessions/new',
        ),
        'HTTP 404 from POST /sessions/new: session_error',
      );
      expect(
        moduleFailure(
          http.Response('{"errcode":"M_UNKNOWN_TOKEN"}', 401),
          'TURN credentials',
        ),
        'HTTP 401 from TURN credentials: M_UNKNOWN_TOKEN',
      );
      expect(
        moduleFailure(
          http.Response('{"errcode":"IM.ZUNO.CALL_FULL"}', 403),
          'POST /sessions/new',
        ),
        'HTTP 403 from POST /sessions/new: IM.ZUNO.CALL_FULL',
      );
    });

    for (final (reason, body) in [
      ('a body that is not JSON', '<html>/sessions/abc</html>'),
      ('a code that is free text', '{"errorCode":"session abc is gone"}'),
      ('a JSON body that is not an object', '["x"]'),
    ]) {
      test('leaves the code out for $reason', () {
        expect(
          moduleFailure(http.Response(body, 502), 'POST /sessions/new'),
          'HTTP 502 from POST /sessions/new',
        );
      });
    }
  });

  group('moduleRefusalOf', () {
    test('reads a full call with the module\'s limit', () {
      final refusal = moduleRefusalOf(
        http.Response(
          '{"errcode":"IM.ZUNO.CALL_FULL","max_participants":8}',
          403,
        ),
      );

      expect(
        refusal,
        isA<CallFullException>().having((e) => e.maxParticipants, 'limit', 8),
      );
    });

    test('reads someone it removed from the call', () {
      final refusal = moduleRefusalOf(
        http.Response(
          '{"errcode":"IM.ZUNO.CALL_REMOVED","error":"Removed from this call"}',
          403,
        ),
      );

      expect(refusal, isA<CallRemovedException>());
    });

    for (final (reason, response) in [
      (
        'a full-call code on another status',
        http.Response(
          '{"errcode":"IM.ZUNO.CALL_FULL","max_participants":8}',
          500,
        ),
      ),
      (
        'a removal code on another status',
        http.Response('{"errcode":"IM.ZUNO.CALL_REMOVED"}', 500),
      ),
      (
        'another refusal',
        http.Response('{"errcode":"M_FORBIDDEN","max_participants":8}', 403),
      ),
      (
        'a full call without the limit',
        http.Response('{"errcode":"IM.ZUNO.CALL_FULL"}', 403),
      ),
      (
        'a limit below one person',
        http.Response(
          '{"errcode":"IM.ZUNO.CALL_FULL","max_participants":0}',
          403,
        ),
      ),
      (
        'a limit that is not a number',
        http.Response(
          '{"errcode":"IM.ZUNO.CALL_FULL","max_participants":"8"}',
          403,
        ),
      ),
      ('a body that is not JSON', http.Response('Forbidden', 403)),
    ]) {
      test('is null for $reason', () {
        expect(moduleRefusalOf(response), isNull);
      });
    }
  });

  group('requestCallRemoval', () {
    Future<void> remove(http.Client mock) => requestCallRemoval(
      buildTestClient()
        ..homeserver = Uri.parse('https://example.org')
        ..accessToken = 'syt_token',
      roomId: '!room:example.org',
      callId: 'call1',
      userId: '@bob:example.org',
      httpClient: mock,
    );

    test('names the room, the call and the person, as the user', () async {
      final requests = <http.Request>[];
      await remove(
        FakeHttpClient((request) async {
          requests.add(request);
          return http.Response('{}', 200);
        }),
      );

      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/_synapse/client/zuno/calls/remove');
      expect(request.url.queryParameters, {
        'room_id': '!room:example.org',
        'call_id': 'call1',
      });
      expect(request.headers['Authorization'], 'Bearer syt_token');
      expect(jsonDecode(request.body), {'user_id': '@bob:example.org'});
    });

    test('a success with an empty body still counts as removed', () async {
      await expectLater(
        remove(FakeHttpClient((request) async => http.Response('', 200))),
        completes,
      );
    });

    test(
      'a refusal fails with the module\'s code and is never retried',
      () async {
        var asked = 0;
        await expectLater(
          remove(
            FakeHttpClient((request) async {
              asked++;
              return http.Response('{"errcode":"M_FORBIDDEN"}', 403);
            }),
          ),
          throwsA(
            isA<CallsModuleException>()
                .having((e) => e.statusCode, 'statusCode', 403)
                .having((e) => e.message, 'message', contains('M_FORBIDDEN')),
          ),
        );
        expect(asked, 1);
      },
    );
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
