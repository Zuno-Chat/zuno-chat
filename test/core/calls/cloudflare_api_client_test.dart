import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zuno/core/calls/cloudflare/cloudflare_api_client.dart';
import 'package:zuno/core/calls/module/calls_module.dart';

import '../../helpers/caught_reports.dart';

const _base = '/_synapse/client/zuno/calls/cloudflare';
const _roomId = '!room:example.org';
const _callId = 'call1';

CloudflareApiClient _client(http.Client mock) => CloudflareApiClient(
  baseUri: () => Uri.parse('https://example.org$_base'),
  authorization: () async => 'Bearer syt_token',
  httpClient: mock,
);

void main() {
  test('createSession opens a session for the room\'s call and returns its '
      'sessionId', () async {
    final mock = MockClient((request) async {
      expect(request.url.path, '$_base/sessions/new');
      expect(request.url.queryParameters, {
        'room_id': _roomId,
        'call_id': _callId,
      });
      expect(request.headers['Authorization'], 'Bearer syt_token');
      return http.Response(jsonEncode({'sessionId': 'sess1'}), 200);
    });
    final sessionId = await _client(mock)
        .createSession(roomId: _roomId, callId: _callId);
    expect(sessionId, 'sess1');
  });

  test('createSession surfaces a full call with the module\'s limit and never '
      'asks again', () async {
    var asked = 0;
    final mock = MockClient((request) async {
      asked++;
      return http.Response(
        jsonEncode({
          'errcode': 'IM.ZUNO.CALL_FULL',
          'error': 'This call is full',
          'max_participants': 8,
        }),
        403,
      );
    });

    await expectLater(
      _client(mock).createSession(roomId: _roomId, callId: _callId),
      throwsA(
        isA<CallFullException>().having(
          (e) => e.maxParticipants,
          'maxParticipants',
          8,
        ),
      ),
    );
    expect(asked, 1);
  });

  test(
    'a removal from the call is reported once and never asked again',
    () async {
      var asked = 0;
      var removed = 0;
      final api = CloudflareApiClient(
        baseUri: () => Uri.parse('https://example.org$_base'),
        authorization: () async => 'Bearer syt_token',
        httpClient: MockClient((request) async {
          asked++;
          return http.Response(
            jsonEncode({
              'errcode': 'IM.ZUNO.CALL_REMOVED',
              'error': 'Removed from this call',
            }),
            403,
          );
        }),
        onRemoved: () => removed++,
      );

      await expectLater(
        api.pullRemoteTracks(
          sessionId: 'sess1',
          tracks: [CfTrack.remote(sessionId: 'sess2', trackName: 'audio')],
        ),
        throwsA(isA<CallRemovedException>()),
      );
      expect(asked, 1);
      expect(removed, 1);
    },
  );

  test('createSession treats any other refusal as a module failure', () async {
    final mock = MockClient(
      (request) async =>
          http.Response(jsonEncode({'errcode': 'M_FORBIDDEN'}), 403),
    );

    await expectLater(
      _client(mock).createSession(roomId: _roomId, callId: _callId),
      throwsA(
        isA<CallsModuleException>().having(
          (e) => e.statusCode,
          'statusCode',
          403,
        ),
      ),
    );
  });

  test(
    'createSession throws CallsModuleException when sessionId is missing',
    () async {
      final mock = MockClient(
        (request) async => http.Response(jsonEncode({}), 200),
      );
      expect(
        _client(mock).createSession(roomId: _roomId, callId: _callId),
        throwsA(isA<CallsModuleException>()),
      );
    },
  );

  test('pullRemoteTracks returns the tracks of a clean response', () async {
    final mock = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'tracks': [
            {'trackName': 'audio', 'mid': '0'},
          ],
        }),
        200,
      ),
    );
    final result = await _client(mock).pullRemoteTracks(
      sessionId: 's1',
      tracks: [CfTrack.remote(sessionId: 'remote', trackName: 'audio')],
    );
    expect(result.tracks.single.mid, '0');
    expect(result.hasError, isFalse);
  });

  test('pushing, pulling, renegotiating or closing throws when the response '
      'carries a top-level errorCode', () async {
    final client = _client(
      MockClient(
        (request) async => http.Response(
          jsonEncode({
            'errorCode': 'session_not_found',
            'errorDescription': 'gone',
            'tracks': [],
          }),
          200,
        ),
      ),
    );

    await expectLater(
      client.pushLocalTracks(
        sessionId: 's1',
        offer: const CfSessionDescription(sdp: 'sdp', type: 'offer'),
        tracks: [CfTrack.local(mid: '0', trackName: 'mic')],
      ),
      throwsA(isA<CallsModuleException>()),
    );
    await expectLater(
      client.pullRemoteTracks(
        sessionId: 's1',
        tracks: [CfTrack.remote(sessionId: 'remote', trackName: 'audio')],
      ),
      throwsA(isA<CallsModuleException>()),
    );
    await expectLater(
      client.renegotiate(
        sessionId: 's1',
        offer: const CfSessionDescription(sdp: 'sdp', type: 'answer'),
      ),
      throwsA(
        isA<CallsModuleException>().having(
          (e) => e.message,
          'message',
          'session_not_found from PUT /sessions/{id}/renegotiate',
        ),
      ),
    );
    await expectLater(
      client.closeTracks(sessionId: 's1', mids: ['0']),
      throwsA(isA<CallsModuleException>()),
    );
  });

  group('what a failure says', () {
    const session = 'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6';
    late List<String> logs;

    setUp(() => logs = recordDebugPrints());

    Future<CallsModuleException> failureOf(http.Response response) async {
      try {
        await _client(MockClient((_) async => response)).pushLocalTracks(
          sessionId: session,
          offer: const CfSessionDescription(sdp: 'sdp', type: 'offer'),
          tracks: [CfTrack.local(mid: '0', trackName: 'audio')],
        );
      } on CallsModuleException catch (error) {
        expect(logs.join('\n'), isNot(contains(session)));
        return error;
      }
      fail('the push did not fail');
    }

    test('an HTTP failure names the route, the status and the code, never '
        'the session or what Cloudflare wrote about it', () async {
      final error = await failureOf(
        http.Response(
          jsonEncode({
            'errorCode': 'session_error',
            'errorDescription': 'session $session is not ready',
          }),
          404,
        ),
      );

      expect(
        error.toString(),
        'CallsModuleException: HTTP 404 from '
        'POST /sessions/{id}/tracks/new: session_error',
      );
      expect(error.statusCode, 404);
    });

    test('a refusal from the homeserver names its Matrix error code', () async {
      final error = await failureOf(
        http.Response(jsonEncode({'errcode': 'M_UNKNOWN_TOKEN'}), 401),
      );

      expect(
        error.message,
        'HTTP 401 from POST /sessions/{id}/tracks/new: M_UNKNOWN_TOKEN',
      );
    });

    test('a body that is not a JSON error leaves the code out', () async {
      final error = await failureOf(
        http.Response('<html>/sessions/$session</html>', 502),
      );

      expect(error.message, 'HTTP 502 from POST /sessions/{id}/tracks/new');
    });

    test('a code that is free text is left out', () async {
      final error = await failureOf(
        http.Response(
          jsonEncode({'errorCode': 'no session /sessions/$session'}),
          404,
        ),
      );

      expect(error.message, 'HTTP 404 from POST /sessions/{id}/tracks/new');
    });

    test('a track error in an accepted answer names the code and the route, '
        'not the description', () async {
      final error = await failureOf(
        http.Response(
          jsonEncode({
            'errorCode': 'session_not_found',
            'errorDescription': 'session $session is gone',
            'tracks': [],
          }),
          200,
        ),
      );

      expect(
        error.message,
        'session_not_found from POST /sessions/{id}/tracks/new',
      );
    });

    test('a retry is logged under the route, not the session', () {
      fakeAsync((async) {
        var calls = 0;
        final mock = MockClient((request) async {
          calls++;
          if (calls == 1) {
            return http.Response(jsonEncode({'retry_after_ms': 100}), 429);
          }
          return http.Response(jsonEncode({'tracks': []}), 200);
        });

        _client(mock).pullRemoteTracks(
          sessionId: session,
          tracks: [CfTrack.remote(sessionId: 'remote', trackName: 'audio')],
        );
        async.elapse(const Duration(seconds: 1));

        expect(calls, 2);
        expect(
          logs.single,
          startsWith('zuno/retry: POST /sessions/{id}/tracks/new failed'),
        );
        expect(logs.single, isNot(contains(session)));
      });
    });

    test('a session the module never names says so without the reply', () {
      expect(
        _client(
          MockClient(
            (_) async => http.Response(
              jsonEncode({'errorDescription': 'quota for $session'}),
              200,
            ),
          ),
        ).createSession(roomId: _roomId, callId: _callId),
        throwsA(
          isA<CallsModuleException>().having(
            (e) => e.message,
            'message',
            'POST /sessions/new returned no session',
          ),
        ),
      );
    });
  });

  test(
    'renegotiate returns null when the response has no sessionDescription',
    () async {
      final mock = MockClient(
        (request) async => http.Response(jsonEncode({}), 200),
      );
      final result = await _client(mock).renegotiate(
        sessionId: 's1',
        offer: const CfSessionDescription(sdp: 'sdp', type: 'answer'),
      );
      expect(result, isNull);
    },
  );

  test(
    'renegotiate returns the new session description when present',
    () async {
      final mock = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'sessionDescription': {'sdp': 'answer-sdp', 'type': 'answer'},
          }),
          200,
        ),
      );
      final result = await _client(mock).renegotiate(
        sessionId: 's1',
        offer: const CfSessionDescription(sdp: 'sdp', type: 'offer'),
      );
      expect(result?.sdp, 'answer-sdp');
    },
  );

  test(
    'closeTracks force-closes the given mids without a description',
    () async {
      final mock = MockClient((request) async {
        expect(request.url.path, '$_base/sessions/s1/tracks/close');
        expect(jsonDecode(request.body), {
          'tracks': [
            {'mid': '0'},
          ],
          'force': true,
        });
        return http.Response(jsonEncode({'tracks': []}), 200);
      });
      await _client(mock).closeTracks(sessionId: 's1', mids: ['0']);
    },
  );

  test('a session request retries once on a SocketException and succeeds', () {
    fakeAsync((async) {
      var calls = 0;
      final mock = MockClient((request) async {
        calls++;
        if (calls == 1) throw const SocketException('connection refused');
        return http.Response(jsonEncode({'sessionId': 'sess1'}), 200);
      });
      String? sessionId;
      _client(mock)
          .createSession(roomId: _roomId, callId: _callId)
          .then((id) => sessionId = id);

      async.elapse(const Duration(seconds: 5));

      expect(calls, 2);
      expect(sessionId, 'sess1');
    });
  });

  test('a track change is never sent twice after a SocketException, since the '
      'SFU may already have applied it', () {
    fakeAsync((async) {
      final paths = <String>[];
      final client = _client(
        MockClient((request) async {
          paths.add(request.url.path.split(_base).last);
          throw paths.length.isEven
              ? http.ClientException('Connection closed while receiving data')
              : const SocketException('connection reset by peer');
        }),
      );
      const description = CfSessionDescription(sdp: 'sdp', type: 'offer');
      final changes = <Future<Object?>>[
        client.pushLocalTracks(
          sessionId: 's1',
          offer: description,
          tracks: [CfTrack.local(mid: '0', trackName: 'audio')],
        ),
        client.pullRemoteTracks(
          sessionId: 's1',
          tracks: [CfTrack.remote(sessionId: 'remote', trackName: 'audio')],
        ),
        client.renegotiate(sessionId: 's1', offer: description),
        client.closeTracks(sessionId: 's1', mids: ['0']),
      ];
      final errors = <Object>[];
      for (final change in changes) {
        change.then((_) {}, onError: errors.add);
      }

      async.elapse(const Duration(seconds: 5));

      expect(paths, [
        '/sessions/s1/tracks/new',
        '/sessions/s1/tracks/new',
        '/sessions/s1/renegotiate',
        '/sessions/s1/tracks/close',
      ]);
      expect(errors, hasLength(4));
    });
  });

  test('a session request also retries a dropped connection the http client '
      'reports as a ClientException, as native clients do', () {
    fakeAsync((async) {
      var calls = 0;
      final mock = MockClient((request) async {
        calls++;
        if (calls == 1) {
          throw http.ClientException('Connection closed before full header');
        }
        return http.Response(jsonEncode({'sessionId': 'sess1'}), 200);
      });
      String? sessionId;
      _client(mock)
          .createSession(roomId: _roomId, callId: _callId)
          .then((id) => sessionId = id);

      async.elapse(const Duration(seconds: 5));

      expect(calls, 2);
      expect(sessionId, 'sess1');
    });
  });

  for (final status in [401, 500]) {
    test('a $status is final: no retry, surfaced as CallsModuleException '
        'with its status', () async {
      var calls = 0;
      final mock = MockClient((request) async {
        calls++;
        return http.Response('{"errcode":"M_UNKNOWN_TOKEN"}', status);
      });

      await expectLater(
        _client(mock).createSession(roomId: _roomId, callId: _callId),
        throwsA(
          isA<CallsModuleException>().having(
            (e) => e.statusCode,
            'statusCode',
            status,
          ),
        ),
      );
      expect(calls, 1);
    });
  }

  test('a 429 waits retry_after_ms and then retries', () {
    fakeAsync((async) {
      var calls = 0;
      final mock = MockClient((request) async {
        calls++;
        if (calls == 1) {
          return http.Response(
            jsonEncode({'errcode': 'M_LIMIT_EXCEEDED', 'retry_after_ms': 400}),
            429,
          );
        }
        return http.Response(jsonEncode({'sessionId': 'sess1'}), 200);
      });
      String? sessionId;
      _client(mock)
          .createSession(roomId: _roomId, callId: _callId)
          .then((id) => sessionId = id);

      async.elapse(const Duration(milliseconds: 399));
      expect(calls, 1);
      async.elapse(const Duration(milliseconds: 1));
      expect(calls, 2);
      expect(sessionId, 'sess1');
    });
  });

  test('a persistent 429 exhausts the attempts and surfaces', () {
    fakeAsync((async) {
      var calls = 0;
      final mock = MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({'errcode': 'M_LIMIT_EXCEEDED', 'retry_after_ms': 100}),
          429,
        );
      });
      Object? error;
      () async {
        try {
          await _client(mock).createSession(roomId: _roomId, callId: _callId);
        } catch (e) {
          error = e;
        }
      }();

      async.elapse(const Duration(seconds: 5));
      expect(calls, 3);
      expect(error, isA<CallsModuleException>());
    });
  });

  test('a request the module never answers fails at the deadline', () {
    fakeAsync((async) {
      var calls = 0;
      final mock = MockClient((request) {
        calls++;
        return Completer<http.Response>().future;
      });
      Object? error;
      () async {
        try {
          await _client(mock).createSession(roomId: _roomId, callId: _callId);
        } catch (e) {
          error = e;
        }
      }();

      async.elapse(const Duration(seconds: 14));
      expect(error, isNull);
      async.elapse(const Duration(seconds: 1));
      expect(error, isA<TimeoutException>());
      expect(calls, 1);
    });
  });

  test('close leaves an injected http client open', () async {
    final injected = _RecordingClient(
      MockClient(
        (_) async => http.Response(jsonEncode({'sessionId': 'sess1'}), 200),
      ),
    );
    _client(injected).close();

    expect(injected.closed, isFalse);
    expect(
      await _client(injected).createSession(roomId: _roomId, callId: _callId),
      'sess1',
    );
  });
}

class _RecordingClient extends http.BaseClient {
  _RecordingClient(this._inner);

  final http.Client _inner;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  @override
  void close() {
    closed = true;
    _inner.close();
  }
}
