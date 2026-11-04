import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:zuno/core/matrix/refresh_deadline_http_client.dart';

import '../../helpers/fake_http.dart';

class _Recording extends http.BaseClient {
  final received = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    received.add(request);
    return http.StreamedResponse(fakeTimeBody(const []), 200);
  }
}

void main() {
  late _Recording server;
  late RefreshDeadlineHttpClient client;

  setUp(() {
    server = _Recording();
    client = RefreshDeadlineHttpClient(server);
  });

  test(
    'sends a refresh with a deadline, keeping its body and headers',
    () async {
      final refresh =
          http.Request(
              'POST',
              Uri.parse('https://example.org/_matrix/client/v3/refresh'),
            )
            ..headers['content-type'] = 'application/json'
            ..body = '{"refresh_token":"r0"}';

      await client.send(refresh);

      final sent = server.received.single as http.Request;
      expect(sent, isA<http.Abortable>());
      expect((sent as http.Abortable).abortTrigger, isNotNull);
      expect(sent.body, '{"refresh_token":"r0"}');
      expect(sent.headers['content-type'], startsWith('application/json'));
    },
  );

  test('leaves every other request as it is', () async {
    final filter = http.Request(
      'POST',
      Uri.parse('https://example.org/_matrix/client/v3/user/me/filter'),
    );

    await client.send(filter);

    expect(server.received.single, same(filter));
  });

  http.Request tokenRequest(String grantType) =>
      http.Request('POST', Uri.parse('https://auth.example.org/token'))
        ..headers['content-type'] = 'application/x-www-form-urlencoded'
        ..bodyFields = {'grant_type': grantType, 'client_id': 'client-1'};

  test('an OAuth refresh grant is aborted at the deadline', () async {
    await client.send(tokenRequest('refresh_token'));

    final sent = server.received.single as http.Request;
    expect(sent, isA<http.Abortable>());
    expect((sent as http.Abortable).abortTrigger, isNotNull);
    expect(sent.bodyFields['grant_type'], 'refresh_token');
    expect(sent.bodyFields['client_id'], 'client-1');
  });

  test('an authorization_code grant is not', () async {
    final exchange = tokenRequest('authorization_code');

    await client.send(exchange);

    expect(server.received.single, same(exchange));
  });

  test('an auth_metadata request is aborted at the deadline', () async {
    await client.send(
      http.Request(
        'GET',
        Uri.parse('https://example.org/_matrix/client/v1/auth_metadata'),
      ),
    );

    final sent = server.received.single as http.Request;
    expect(sent, isA<http.Abortable>());
    expect((sent as http.Abortable).abortTrigger, isNotNull);
  });

  test('an auth_metadata request under an API path prefix is aborted at the '
      'deadline too', () async {
    await client.send(
      http.Request(
        'GET',
        Uri.parse('https://example.org/matrix/_matrix/client/v1/auth_metadata'),
      ),
    );

    final sent = server.received.single as http.Request;
    expect(sent, isA<http.Abortable>());
    expect((sent as http.Abortable).abortTrigger, isNotNull);
  });

  test('another GET is not', () async {
    final versions = http.Request(
      'GET',
      Uri.parse('https://example.org/_matrix/client/versions'),
    );

    await client.send(versions);

    expect(server.received.single, same(versions));
  });
}
