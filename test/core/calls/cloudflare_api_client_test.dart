import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:zuno/core/calls/cloudflare/calls_gateway_credentials.dart';
import 'package:zuno/core/calls/cloudflare/cloudflare_api_client.dart';

CloudflareApiClient _client(
  http.Client mock, {
  GatewayAuthorizationProvider? authorizationProvider,
}) => CloudflareApiClient(
  baseUri: Uri.parse('https://example.org/calls'),
  authorizationProvider:
      authorizationProvider ??
      ({bool refresh = false}) async => 'Bearer syt_token',
  httpClient: mock,
);

void main() {
  test('createSession returns the sessionId from a 200 response', () async {
    final mock = MockClient((request) async {
      expect(request.url.path, '/calls/sessions/new');
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

  test('a non-2xx HTTP status throws CloudflareCallsException', () async {
    final mock = MockClient(
      (request) async => http.Response('server error', 500),
    );
    expect(
      _client(mock).createSession(),
      throwsA(isA<CloudflareCallsException>()),
    );
  });

  test(
    'pushLocalTracks throws when the response carries a per-track errorCode',
    () async {
      final mock = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'errorCode': 'bad_track',
            'errorDescription': 'nope',
            'tracks': [],
          }),
          200,
        ),
      );
      expect(
        _client(mock).pushLocalTracks(
          sessionId: 's1',
          offer: const CfSessionDescription(sdp: 'sdp', type: 'offer'),
          tracks: [CfTrack.local(mid: '0', trackName: 'mic')],
        ),
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

  test(
    'pullRemoteTracks throws when the response carries a top-level errorCode',
    () async {
      final mock = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'errorCode': 'session_not_found',
            'errorDescription': 'gone',
            'tracks': [],
          }),
          200,
        ),
      );
      await expectLater(
        _client(mock).pullRemoteTracks(
          sessionId: 's1',
          tracks: [CfTrack.remote(sessionId: 'remote', trackName: 'audio')],
        ),
        throwsA(isA<CloudflareCallsException>()),
      );
    },
  );

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
        expect(request.url.path, '/calls/sessions/s1/tracks/close');
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

  test('closeTracks throws CloudflareCallsException on a non-2xx response', () {
    final mock = MockClient(
      (request) async => http.Response('server error', 500),
    );
    expect(
      _client(mock).closeTracks(
        sessionId: 's1',
        mids: ['0'],
        sessionDescription: const CfSessionDescription(
          sdp: 'sdp',
          type: 'offer',
        ),
      ),
      throwsA(isA<CloudflareCallsException>()),
    );
  });

  test('closeTracks surfaces a transport failure as-is', () {
    final mock = MockClient(
      (request) async =>
          throw http.ClientException('Connection closed before full header'),
    );
    expect(
      _client(mock).closeTracks(
        sessionId: 's1',
        mids: ['0'],
        sessionDescription: const CfSessionDescription(
          sdp: 'sdp',
          type: 'offer',
        ),
      ),
      throwsA(isA<http.ClientException>()),
    );
  });

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

  test('exhausts retries and rethrows a persistent SocketException', () {
    fakeAsync((async) {
      var calls = 0;
      final mock = MockClient((request) async {
        calls++;
        throw const SocketException('connection refused');
      });
      Object? error;
      () async {
        try {
          await _client(mock).createSession();
        } catch (e) {
          error = e;
        }
      }();

      async.elapse(const Duration(seconds: 10));

      expect(calls, greaterThan(1));
      expect(error, isA<SocketException>());
    });
  });

  test('does not retry a non-2xx HTTP status', () {
    fakeAsync((async) {
      var calls = 0;
      final mock = MockClient((request) async {
        calls++;
        return http.Response('server error', 500);
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
      expect(error, isA<CloudflareCallsException>());
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

  test('a 401 refreshes the authorization once and retries', () async {
    final refreshes = <bool>[];
    var calls = 0;
    final mock = MockClient((request) async {
      calls++;
      if (request.headers['Authorization'] == 'Bearer fresh') {
        return http.Response(jsonEncode({'sessionId': 'sess1'}), 200);
      }
      return http.Response('expired', 401);
    });
    final client = _client(
      mock,
      authorizationProvider: ({bool refresh = false}) async {
        refreshes.add(refresh);
        return refresh ? 'Bearer fresh' : 'Bearer stale';
      },
    );
    expect(await client.createSession(), 'sess1');
    expect(refreshes, [false, true]);
    expect(calls, 2);
  });

  test('a second 401 surfaces as CloudflareCallsException', () async {
    var calls = 0;
    final mock = MockClient((request) async {
      calls++;
      return http.Response('still expired', 401);
    });
    await expectLater(
      _client(mock).createSession(),
      throwsA(isA<CloudflareCallsException>()),
    );
    expect(calls, 2);
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
