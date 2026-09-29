import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/matrix/fresh_token_http_client.dart';

void main() {
  late List<http.BaseRequest> sent;
  late String? token;
  late int refreshes;
  late Future<void> Function() refresh;
  late FreshTokenHttpClient client;

  setUp(() {
    sent = [];
    token = 'old';
    refreshes = 0;
    refresh = () async => token = 'new';
    client = FreshTokenHttpClient(
      MockClient((request) async {
        sent.add(request);
        return http.Response('{}', 200);
      }),
      accessToken: () => token,
      ensureFresh: () {
        refreshes++;
        return refresh();
      },
    );
  });

  http.Request request({String? authorization}) =>
      http.Request('GET', Uri.parse('https://example.org/_matrix/x'))
        ..headers.addAll({'Authorization': ?authorization});

  test(
    'a request with a token about to expire goes out with the new one',
    () async {
      await client.send(request(authorization: 'Bearer old'));

      expect(refreshes, 1);
      expect(sent.single.headers['authorization'], 'Bearer new');
      expect(
        sent.single.headers.keys.where(
          (k) => k.toLowerCase() == 'authorization',
        ),
        hasLength(1),
      );
    },
  );

  test('a token still fresh is sent as it is', () async {
    refresh = () async {};

    await client.send(request(authorization: 'Bearer old'));

    expect(refreshes, 1);
    expect(sent.single.headers['authorization'], 'Bearer old');
  });

  test('a request without a token does not wait for a refresh', () async {
    await client.send(request());

    expect(refreshes, 0);
    expect(sent.single.headers['authorization'], isNull);
  });

  test('a request carrying some other token is left alone', () async {
    await client.send(request(authorization: 'Bearer elsewhere'));

    expect(refreshes, 0);
    expect(sent.single.headers['authorization'], 'Bearer elsewhere');
  });

  test('signed out, nothing waits for a refresh', () async {
    token = null;

    await client.send(request(authorization: 'Bearer old'));

    expect(refreshes, 0);
    expect(sent.single.headers['authorization'], 'Bearer old');
  });

  test(
    'a refresh the server refuses fails the request with its error',
    () async {
      refresh = () async => throw MatrixException.fromJson({
        'errcode': 'M_UNKNOWN_TOKEN',
        'error': 'refresh token revoked',
      });

      await expectLater(
        client.send(request(authorization: 'Bearer old')),
        throwsA(isA<MatrixException>()),
      );
      expect(sent, isEmpty);
    },
  );
}
