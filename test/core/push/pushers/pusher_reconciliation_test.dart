import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:zuno/core/push/pushers/pusher_reconciliation.dart';

import '../../../helpers/fake_http.dart';
import '../../../helpers/fake_matrix.dart';
import '../../../helpers/pusher_recording_client.dart';

http.Response _ok(Object? body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  const appId = 'im.zuno.chat.android';
  const pushkey = 'fZx9Q:APA91bHun4MxP5egoKMwt2K';

  Client clientAnswering(Future<http.Response> Function() respond) =>
      buildTestClient(httpClient: FakeHttpClient((_) => respond()))
        ..homeserver = Uri.parse('https://example.org')
        ..accessToken = 'token';

  final gateway = Uri.parse('https://push.example.org/_matrix/push/v1/notify');

  Future<PusherCheck> check(Client client) => checkPusherOnServer(
    client,
    appId: appId,
    pushkey: pushkey,
    gatewayUrl: gateway,
  );

  Client listing(List<Object?> pushers) =>
      clientAnswering(() async => _ok({'pushers': pushers}));

  test('this device sending event ids through this gateway matches', () async {
    final client = listing([
      livePusherJson(
        appId: 'im.zuno.chat.unifiedpush',
        pushkey: 'https://ntfy.sh/upOther',
      ),
      livePusherJson(appId: appId, pushkey: pushkey, url: '$gateway'),
    ]);

    expect(await check(client), PusherCheck.matches);
  });

  test('missing when the homeserver lists only other devices or other '
      'apps', () async {
    expect(
      await check(
        listing([
          livePusherJson(appId: appId, pushkey: 'some-other-token'),
          livePusherJson(appId: 'org.example.other', pushkey: pushkey),
        ]),
      ),
      PusherCheck.missing,
    );
  });

  test('missing for an account with no pushers at all, since an empty list '
      'is a definite answer, not a failed read', () async {
    expect(await check(listing(const [])), PusherCheck.missing);
  });

  test('outdated when it misses the gateway or the format', () async {
    expect(
      await check(
        listing([
          livePusherJson(
            appId: appId,
            pushkey: pushkey,
            url: 'https://old.example.org/_matrix/push/v1/notify',
          ),
        ]),
      ),
      PusherCheck.outdated,
    );
    expect(
      await check(
        listing([
          livePusherJson(
            appId: appId,
            pushkey: pushkey,
            url: '$gateway',
            format: 'full',
          ),
        ]),
      ),
      PusherCheck.outdated,
    );
  });

  test('without a known gateway only the format counts', () async {
    final client = listing([
      livePusherJson(
        appId: appId,
        pushkey: pushkey,
        url: 'https://anywhere.example.org/_matrix/push/v1/notify',
      ),
    ]);

    expect(
      await checkPusherOnServer(
        client,
        appId: appId,
        pushkey: pushkey,
        gatewayUrl: null,
      ),
      PusherCheck.matches,
    );
  });

  test('unknown when the homeserver cannot be reached', () async {
    final client = clientAnswering(
      () async => throw http.ClientException('offline'),
    );

    expect(await check(client), PusherCheck.unknown);
  });

  test('unknown when the response carries no pushers list', () async {
    expect(
      await check(clientAnswering(() async => _ok({'nonsense': true}))),
      PusherCheck.unknown,
    );
  });

  test('fetchPushers skips entries that are not pushers', () async {
    final client = clientAnswering(
      () async => _ok({
        'pushers': [
          serverPusherJson(appId: appId, pushkey: pushkey),
          'not a pusher',
        ],
      }),
    );

    final pushers = await fetchPushers(client);
    expect(pushers, hasLength(1));
    expect(pushers!.single.pushkey, pushkey);
  });
}
