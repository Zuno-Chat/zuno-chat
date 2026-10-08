import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zuno/core/push/voip/voip_server.dart';
import 'package:zuno/core/push/zuno_push_api.dart';

import '../../../helpers/fake_matrix.dart';

http.Response _module(Object? body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'x-zuno-push': '1', 'content-type': 'application/json'},
);

ZunoPushVoipServer _server(
  Future<http.Response> Function(http.Request request) answer, {
  List<http.Request>? requests,
}) => ZunoPushVoipServer.withApi(
  () => ZunoPushApi(
    homeserver: Uri.parse('https://matrix.example.org'),
    bearer: () async => 'Bearer syt_token',
    httpClient: MockClient((request) {
      requests?.add(request);
      return answer(request);
    }),
  ),
);

Future<VoipServerReply> _put(ZunoPushVoipServer server) => server.putVoip(
  appId: 'im.zuno.chat.ios.voip',
  pushkey: 'AQID',
  kid: 16909060,
  key: base64Encode(List.filled(32, 7)),
);

void main() {
  test('an accepted registration carries the acknowledged kid and the server '
      'time', () async {
    final requests = <http.Request>[];
    final server = _server(
      (_) async => _module({'kid': 16909060, 'server_ts': 1790000000123}),
      requests: requests,
    );

    final reply = await _put(server);

    expect(reply, isA<VoipServerAccepted>());
    reply as VoipServerAccepted;
    expect(reply.kid, 16909060);
    expect(reply.serverTs, 1790000000123);
    expect(requests.single.method, 'PUT');
    expect(requests.single.url.path, '/_synapse/client/zuno/push/v1/voip');
    expect(jsonDecode(requests.single.body), {
      'app_id': 'im.zuno.chat.ios.voip',
      'pushkey': 'AQID',
      'kid': 16909060,
      'key': base64Encode(List.filled(32, 7)),
    });
  });

  test(
    'deleting the token and the device are accepted without a kid',
    () async {
      final requests = <http.Request>[];
      final server = _server(
        (_) async => _module({'server_ts': 5}),
        requests: requests,
      );

      final voip = await server.deleteVoip();
      final device = await server.deleteDevice();

      expect((voip as VoipServerAccepted).kid, isNull);
      expect((device as VoipServerAccepted).serverTs, 5);
      expect(requests.map((r) => '${r.method} ${r.url.pathSegments.last}'), [
        'DELETE voip',
        'DELETE device',
      ]);
    },
  );

  test(
    'a route failure without the module header is quietly unreachable',
    () async {
      final server = _server(
        (_) async => http.Response(
          jsonEncode({'errcode': 'M_UNRECOGNIZED', 'error': 'Unrecognized'}),
          404,
        ),
      );

      expect(await _put(server), isA<VoipServerUnreachable>());
    },
  );

  test(
    'a network error and a server error are unreachable, not refused',
    () async {
      final offline = _server(
        (_) async => throw http.ClientException('offline'),
      );
      final crashed = _server(
        (_) async =>
            _module({'errcode': 'M_UNKNOWN', 'error': 'boom'}, status: 500),
      );

      expect(await _put(offline), isA<VoipServerUnreachable>());
      expect(await _put(crashed), isA<VoipServerUnreachable>());
    },
  );

  test(
    'a module still starting is backed off quietly, never refused',
    () async {
      final server = _server(
        (_) async => _module({
          'errcode': 'IM.ZUNO.STARTING',
          'error': 'zuno_push is still starting',
        }, status: 503),
      );

      expect(await _put(server), isA<VoipServerUnreachable>());
      expect(
        voipServerReply(
          const ZunoPushFailure<int>(
            ZunoPushFailureKind.disabled,
            status: 503,
            errcode: 'IM.ZUNO.STARTING',
          ),
        ),
        isA<VoipServerUnreachable>(),
      );
    },
  );

  test('a rate limit is unreachable for as long as the server asks', () async {
    final server = _server(
      (_) async => _module({
        'errcode': 'M_LIMIT_EXCEEDED',
        'error': 'slow down',
        'retry_after_ms': 4000,
      }, status: 429),
    );

    final reply = await _put(server);

    expect(
      (reply as VoipServerUnreachable).retryAfter,
      const Duration(seconds: 4),
    );
  });

  test('a module refusal keeps its status, errcode and error', () async {
    final invalid = _server(
      (_) async => _module({
        'errcode': 'M_INVALID_PARAM',
        'error': 'bad key',
      }, status: 400),
    );
    final disabled = _server(
      (_) async => _module({
        'errcode': 'IM.ZUNO.PUSH_DISABLED',
        'error': 'off',
      }, status: 503),
    );

    final first = await _put(invalid) as VoipServerRefused;
    final second = await _put(disabled) as VoipServerRefused;

    expect(
      (first.status, first.errcode, first.error),
      (400, 'M_INVALID_PARAM', 'bad key'),
    );
    expect(
      (second.status, second.errcode, second.error),
      (503, 'IM.ZUNO.PUSH_DISABLED', 'off'),
    );
  });

  test('a module answer outside the contract is refused', () async {
    final server = _server(
      (_) async => _module({'kid': 'one', 'server_ts': 1}),
    );

    final reply = await _put(server) as VoipServerRefused;

    expect(reply.errcode, 'malformed');
  });

  test('a client without a homeserver is unreachable', () async {
    final server = ZunoPushVoipServer(buildTestClient());

    expect(await server.deleteDevice(), isA<VoipServerUnreachable>());
  });
}
