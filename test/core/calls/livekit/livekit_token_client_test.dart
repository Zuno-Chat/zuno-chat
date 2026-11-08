import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/calls/livekit/livekit_token_client.dart';
import 'package:zuno/core/calls/module/calls_module.dart';

import '../../../helpers/fake_http.dart';
import '../../../helpers/fake_matrix.dart';

const _spec = (roomId: '!room:example.org', callId: 'call1');
const _secret = 'lk.secret.token';

Client _client() => buildTestClient()
  ..homeserver = Uri.parse('https://example.org')
  ..accessToken = 'syt_token';

http.Response _grant({String url = 'wss://lk.example.org'}) =>
    http.Response(jsonEncode({'url': url, 'token': _secret}), 200);

void main() {
  test('returns url and token and sends room_id and call_id', () async {
    late http.Request seen;
    final grant = await fetchLiveKitGrant(
      _client(),
      _spec,
      httpClient: FakeHttpClient((request) async {
        seen = request;
        return _grant();
      }),
    );

    expect(grant.url, Uri.parse('wss://lk.example.org'));
    expect(grant.token, _secret);
    expect(seen.method, 'POST');
    expect(seen.url.path, '/_synapse/client/zuno/calls/livekit/token');
    expect(seen.url.queryParameters, {
      'room_id': '!room:example.org',
      'call_id': 'call1',
    });
    expect(seen.headers['Authorization'], 'Bearer syt_token');
  });

  test('403 IM.ZUNO.CALL_FULL throws CallFullException(6)', () async {
    await expectLater(
      fetchLiveKitGrant(
        _client(),
        _spec,
        httpClient: FakeHttpClient(
          (_) async => http.Response(
            jsonEncode({'errcode': 'IM.ZUNO.CALL_FULL', 'max_participants': 6}),
            403,
          ),
        ),
      ),
      throwsA(
        isA<CallFullException>().having((e) => e.maxParticipants, 'max', 6),
      ),
    );
  });

  test('403 IM.ZUNO.CALL_REMOVED throws CallRemovedException', () async {
    await expectLater(
      fetchLiveKitGrant(
        _client(),
        _spec,
        httpClient: FakeHttpClient(
          (_) async => http.Response(
            jsonEncode({'errcode': 'IM.ZUNO.CALL_REMOVED'}),
            403,
          ),
        ),
      ),
      throwsA(isA<CallRemovedException>()),
    );
  });

  test('404 M_UNRECOGNIZED throws CallsRouteGone', () async {
    await expectLater(
      fetchLiveKitGrant(
        _client(),
        _spec,
        httpClient: FakeHttpClient(
          (_) async =>
              http.Response(jsonEncode({'errcode': 'M_UNRECOGNIZED'}), 404),
        ),
      ),
      throwsA(isA<CallsRouteGone>()),
    );
  });

  test(
    'another failure throws CallsModuleException named for the route',
    () async {
      await expectLater(
        fetchLiveKitGrant(
          _client(),
          _spec,
          httpClient: FakeHttpClient((_) async => http.Response('boom', 500)),
        ),
        throwsA(
          isA<CallsModuleException>()
              .having((e) => e.statusCode, 'status', 500)
              .having(
                (e) => e.message,
                'message',
                'HTTP 500 from POST /livekit/token',
              ),
        ),
      );
    },
  );

  test('429 retries after retry_after_ms', () {
    fakeAsync((async) {
      var calls = 0;
      LiveKitGrant? grant;
      fetchLiveKitGrant(
        _client(),
        _spec,
        httpClient: FakeHttpClient((_) async {
          calls++;
          if (calls == 1) {
            return http.Response(
              jsonEncode({
                'errcode': 'M_LIMIT_EXCEEDED',
                'retry_after_ms': 400,
              }),
              429,
            );
          }
          return _grant();
        }),
      ).then((value) => grant = value);

      async.elapse(const Duration(milliseconds: 399));
      expect(calls, 1);
      async.elapse(const Duration(milliseconds: 1));
      expect(calls, 2);
      expect(grant?.token, _secret);
    });
  });

  test('a token request lost to the network is sent again', () {
    fakeAsync((async) {
      var calls = 0;
      LiveKitGrant? grant;
      fetchLiveKitGrant(
        _client(),
        _spec,
        httpClient: FakeHttpClient((_) async {
          if (++calls == 1) throw const SocketException('reset');
          return _grant();
        }),
      ).then((value) => grant = value);

      async.elapse(const Duration(seconds: 2));

      expect(calls, 2);
      expect(grant?.token, _secret);
    });
  });

  for (final (reason, response) in [
    ('a ws url', _grant(url: 'ws://lk.example.org')),
    ('an https url', _grant(url: 'https://lk.example.org')),
    ('a url without a scheme', _grant(url: 'lk.example.org')),
    ('a missing url', http.Response(jsonEncode({'token': _secret}), 200)),
    (
      'a missing token',
      http.Response(jsonEncode({'url': 'wss://lk.example.org'}), 200),
    ),
    (
      'an empty token',
      http.Response(
        jsonEncode({'url': 'wss://lk.example.org', 'token': ''}),
        200,
      ),
    ),
  ]) {
    test('$reason is refused, and the message holds neither value', () async {
      Object? error;
      try {
        await fetchLiveKitGrant(
          _client(),
          _spec,
          httpClient: FakeHttpClient((_) async => response),
        );
      } on Object catch (e) {
        error = e;
      }

      expect(error, isA<CallsModuleException>());
      expect(error.toString(), isNot(contains(_secret)));
      expect(error.toString(), isNot(contains('lk.example.org')));
    });
  }

  test('exception text never contains the token', () async {
    Object? error;
    try {
      await fetchLiveKitGrant(
        _client(),
        _spec,
        httpClient: FakeHttpClient(
          (_) async => http.Response(
            jsonEncode({'errcode': 'M_UNKNOWN', 'token': _secret}),
            500,
          ),
        ),
      );
    } on Object catch (e) {
      error = e;
    }

    expect(error.toString(), isNot(contains(_secret)));
  });
}
