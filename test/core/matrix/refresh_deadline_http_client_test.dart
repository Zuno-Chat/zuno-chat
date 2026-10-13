import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:zuno/core/matrix/refresh_deadline_http_client.dart';

class _Recording extends http.BaseClient {
  final received = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    received.add(request);
    return http.StreamedResponse(const Stream.empty(), 200);
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
}
