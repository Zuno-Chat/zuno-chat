import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:zuno/core/push/pusher_reconciliation.dart';

import '../../helpers/fake_matrix.dart';

Map<String, Object?> _pusher({
  required String appId,
  required String pushkey,
}) => {
  'app_id': appId,
  'pushkey': pushkey,
  'app_display_name': 'Zuno Chat',
  'device_display_name': 'Phone',
  'kind': 'http',
  'lang': 'en',
};

http.Response _ok(Object? body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  const appId = 'im.zuno.chat.android';
  const pushkey = 'fZx9Q:APA91bHun4MxP5egoKMwt2K';

  Client clientAnswering(Future<http.Response> Function() respond) =>
      buildTestClient(httpClient: MockClient((_) => respond()))
        ..homeserver = Uri.parse('https://example.org')
        ..accessToken = 'token';

  test('true when the homeserver still lists this device\'s pusher', () async {
    final client = clientAnswering(
      () async => _ok({
        'pushers': [
          _pusher(
            appId: 'im.zuno.chat.unifiedpush',
            pushkey: 'https://ntfy.sh/upOther',
          ),
          _pusher(appId: appId, pushkey: pushkey),
        ],
      }),
    );

    expect(
      await pusherIsRegistered(client, appId: appId, pushkey: pushkey),
      isTrue,
    );
  });

  test('false when the homeserver lists only other devices', () async {
    final client = clientAnswering(
      () async => _ok({
        'pushers': [
          _pusher(appId: appId, pushkey: 'some-other-token'),
        ],
      }),
    );

    expect(
      await pusherIsRegistered(client, appId: appId, pushkey: pushkey),
      isFalse,
    );
  });

  test('false for an account with no pushers at all — an empty list is a '
      'definite answer, not a failed read', () async {
    final client = clientAnswering(() async => _ok({'pushers': const []}));

    expect(
      await pusherIsRegistered(client, appId: appId, pushkey: pushkey),
      isFalse,
    );
  });

  test('false when another app happens to share our pushkey', () async {
    final client = clientAnswering(
      () async => _ok({
        'pushers': [_pusher(appId: 'org.example.other', pushkey: pushkey)],
      }),
    );

    expect(
      await pusherIsRegistered(client, appId: appId, pushkey: pushkey),
      isFalse,
    );
  });

  test('null when the homeserver cannot be reached', () async {
    final client = clientAnswering(
      () async => throw http.ClientException('offline'),
    );

    expect(
      await pusherIsRegistered(client, appId: appId, pushkey: pushkey),
      isNull,
    );
  });

  test('null when the response carries no pushers list', () async {
    final client = clientAnswering(() async => _ok({'nonsense': true}));

    expect(
      await pusherIsRegistered(client, appId: appId, pushkey: pushkey),
      isNull,
    );
  });

  test('fetchPushers parses what it can and returns null when it cannot',
      () async {
    final client = clientAnswering(
      () async => _ok({
        'pushers': [
          _pusher(appId: appId, pushkey: pushkey),
          'not a pusher',
        ],
      }),
    );

    final pushers = await fetchPushers(client);
    expect(pushers, hasLength(1));
    expect(pushers!.single.pushkey, pushkey);

    final broken = clientAnswering(() async => http.Response('<html>', 500));
    expect(await fetchPushers(broken), isNull);
  });
}
