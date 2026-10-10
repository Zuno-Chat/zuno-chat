import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:zuno/core/calls/cloudflare/cloudflare_api_client.dart';

const _base = '/_synapse/client/zuno/calls/cloudflare';

CloudflareApiClient _client(http.Client mock) => CloudflareApiClient(
  baseUri: () => Uri.parse('https://example.org$_base'),
  authorization: () async => 'Bearer syt_token',
  httpClient: mock,
);

void main() {
  test('createSession returns the sessionId from a 200 response', () async {
    final mock = MockClient((request) async {
      expect(request.url.path, '$_base/sessions/new');
      expect(request.headers['Authorization'], 'Bearer syt_token');
      return http.Response(jsonEncode({'sessionId': 'sess1'}), 200);
    });
    final sessionId = await _client(mock).createSession();
    expect(sessionId, 'sess1');
  });

  test(
    'createSession throws CloudflareCallsException when sessionId is missing',
    () async {
      final mock = MockClient(
        (request) async => http.Response(jsonEncode({}), 200),
      );
      expect(
        _client(mock).createSession(),
        throwsA(isA<CloudflareCallsException>()),
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

  test('pushing, pulling or renegotiating throws when the response carries '
      'a top-level errorCode', () async {
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
      throwsA(isA<CloudflareCallsException>()),
    );
    await expectLater(
      client.pullRemoteTracks(
        sessionId: 's1',
        tracks: [CfTrack.remote(sessionId: 'remote', trackName: 'audio')],
      ),
      throwsA(isA<CloudflareCallsException>()),
    );
    await expectLater(
      client.renegotiate(
        sessionId: 's1',
        offer: const CfSessionDescription(sdp: 'sdp', type: 'answer'),
      ),
      throwsA(
        isA<CloudflareCallsException>().having(
          (e) => e.message,
          'message',
          'session_not_found: gone',
        ),
      ),
    );
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
    'closeTracks posts the given mids, force flag, and sessionDescription',
    () async {
      final mock = MockClient((request) async {
        expect(request.url.path, '$_base/sessions/s1/tracks/close');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['force'], isTrue);
        expect(body['tracks'], [
          {'mid': '0'},
        ]);
        expect(body['sessionDescription'], {'sdp': 'sdp', 'type': 'offer'});
        return http.Response(jsonEncode({'tracks': []}), 200);
      });
      final result = await _client(mock).closeTracks(
        sessionId: 's1',
        mids: ['0'],
        force: true,
        sessionDescription: const CfSessionDescription(
          sdp: 'sdp',
          type: 'offer',
        ),
      );
      expect(result.hasError, isFalse);
    },
  );

  test('retries once on a SocketException and succeeds', () {
    fakeAsync((async) {
      var calls = 0;
      final mock = MockClient((request) async {
        calls++;
        if (calls == 1) throw const SocketException('connection refused');
        return http.Response(jsonEncode({'sessionId': 'sess1'}), 200);
      });
      String? sessionId;
      _client(mock).createSession().then((id) => sessionId = id);

      async.elapse(const Duration(seconds: 5));

      expect(calls, 2);
      expect(sessionId, 'sess1');
    });
  });

  test('does not retry a generic http.ClientException', () {
    fakeAsync((async) {
      var calls = 0;
      final mock = MockClient((request) async {
        calls++;
        throw http.ClientException('Connection closed before full header');
      });
      Object? error;
      () async {
        try {
          await _client(mock).createSession();
        } catch (e) {
          error = e;
        }
      }();

      async.elapse(const Duration(seconds: 5));

      expect(calls, 1);
      expect(error, isA<http.ClientException>());
    });
  });

  for (final status in [401, 500]) {
    test('a $status is final: no retry, surfaced as CloudflareCallsException '
        'with its status', () async {
      var calls = 0;
      final mock = MockClient((request) async {
        calls++;
        return http.Response('{"errcode":"M_UNKNOWN_TOKEN"}', status);
      });

      await expectLater(
        _client(mock).createSession(),
        throwsA(
          isA<CloudflareCallsException>().having(
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
      _client(mock).createSession().then((id) => sessionId = id);

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
          await _client(mock).createSession();
        } catch (e) {
          error = e;
        }
      }();

      async.elapse(const Duration(seconds: 5));
      expect(calls, 3);
      expect(error, isA<CloudflareCallsException>());
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
          await _client(mock).createSession();
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
    expect(await _client(injected).createSession(), 'sess1');
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
