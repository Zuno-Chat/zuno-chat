import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/calls/call_liveness.dart';
import 'package:zuno/core/calls/models/call_kind.dart';

import '../../helpers/fake_matrix.dart';

Client _clientAnswering(FutureOr<http.Response> Function(http.Request) answer) {
  final client = buildTestClient(
    userId: '@me:zuno.im',
    httpClient: MockClient((request) async => answer(request)),
  );
  client.baseUri = Uri.parse('https://zuno.im');
  client.bearerToken = 'token';
  return client;
}

Future<CallLiveness> _check(Client client) => checkCallLiveness(
  client,
  roomId: '!r:zuno.im',
  callId: 'c1',
  callerId: '@alice:zuno.im',
);

void main() {
  test('asks the server for the caller\'s own membership in that room', () async {
    late Uri asked;
    final client = _clientAnswering((request) {
      asked = request.url;
      return http.Response(jsonEncode({'memberships': []}), 200);
    });

    await _check(client);

    expect(
      Uri.decodeComponent(asked.path),
      '/_matrix/client/v3/rooms/!r:zuno.im/state/m.call.member/@alice:zuno.im',
    );
  });

  test(
    'a membership that names the call keeps it alive, expired or not',
    () async {
      final client = _clientAnswering(
        (_) => http.Response(
          jsonEncode({
            'memberships': [
              {
                'call_id': 'c1',
                'device_id': 'D',
                'kind': 'voice',
                'expires_ts': 1,
              },
            ],
          }),
          200,
        ),
      );

      expect(await _check(client), CallLiveness.live);
    },
  );

  test('memberships for other calls mean this one is gone', () async {
    final client = _clientAnswering(
      (_) => http.Response(
        jsonEncode({
          'memberships': [
            {'call_id': 'other'},
          ],
        }),
        200,
      ),
    );

    expect(await _check(client), CallLiveness.gone);
  });

  test('a caller with no membership event at all is gone', () async {
    final client = _clientAnswering(
      (_) => http.Response(
        jsonEncode({'errcode': 'M_NOT_FOUND', 'error': 'not found'}),
        404,
      ),
    );

    expect(await _check(client), CallLiveness.gone);
  });

  test(
    'a proxy page or server error proves nothing, so the answer goes on',
    () async {
      final client = _clientAnswering(
        (_) => http.Response('<html>Bad gateway</html>', 502),
      );

      expect(await _check(client), CallLiveness.unknown);
    },
  );

  test('a slow server proves nothing either', () {
    fakeAsync((async) {
      final client = _clientAnswering((_) => Completer<http.Response>().future);
      CallLiveness? liveness;
      unawaited(_check(client).then((answer) => liveness = answer));

      async.elapse(callLivenessTimeout - const Duration(milliseconds: 1));
      expect(liveness, isNull);

      async.elapse(const Duration(milliseconds: 1));
      expect(liveness, CallLiveness.unknown);
    });
  });

  test('without a caller there is nothing to ask', () async {
    var asked = false;
    final client = _clientAnswering((_) {
      asked = true;
      return http.Response('{}', 200);
    });

    expect(
      await checkCallLiveness(
        client,
        roomId: '!r:zuno.im',
        callId: 'c1',
        callerId: '',
      ),
      CallLiveness.unknown,
    );
    expect(asked, isFalse);
  });

  test('reads memberships without trusting their shape', () {
    expect(rawMemberships({'memberships': 'nope'}), isEmpty);
    expect(
      rawMemberships({
        'memberships': [
          'junk',
          {'call_id': 3},
          {'call_id': 'c1', 'kind': 'video', 'created_ts': 42},
          {'call_id': 'c2'},
        ],
      }),
      [
        (callId: 'c1', kind: CallKind.video, createdTs: 42),
        (callId: 'c2', kind: CallKind.voice, createdTs: 0),
      ],
    );
  });
}
