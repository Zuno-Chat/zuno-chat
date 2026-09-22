import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:zuno/core/push/matrix_unified_push_gateway.dart';

void main() {
  final endpoint = Uri.parse('https://ntfy.example.org/up/abc123?token=xyz');

  test(
    'discovers a built-in gateway when the endpoint host answers correctly',
    () async {
      final mock = MockClient((request) async {
        expect(
          request.url.toString(),
          'https://ntfy.example.org/_matrix/push/v1/notify',
        );
        return http.Response(
          jsonEncode({
            'unifiedpush': {'gateway': 'matrix'},
          }),
          200,
        );
      });
      final gateway = await resolveMatrixGatewayUrl(endpoint, httpClient: mock);
      expect(
        gateway,
        Uri.parse('https://ntfy.example.org/_matrix/push/v1/notify'),
      );
    },
  );

  test('falls back to the public gateway on a non-200 response', () async {
    final mock = MockClient((request) async => http.Response('not found', 404));
    final gateway = await resolveMatrixGatewayUrl(endpoint, httpClient: mock);
    expect(gateway, fallbackMatrixGatewayUrl);
  });

  test(
    'falls back to the public gateway on an unexpected JSON shape',
    () async {
      final mock = MockClient(
        (request) async => http.Response(jsonEncode({'unrelated': true}), 200),
      );
      final gateway = await resolveMatrixGatewayUrl(endpoint, httpClient: mock);
      expect(gateway, fallbackMatrixGatewayUrl);
    },
  );

  test('falls back to the public gateway on malformed JSON', () async {
    final mock = MockClient((request) async => http.Response('not json', 200));
    final gateway = await resolveMatrixGatewayUrl(endpoint, httpClient: mock);
    expect(gateway, fallbackMatrixGatewayUrl);
  });

  test('falls back to the public gateway when the request throws', () async {
    final mock = MockClient((request) async => throw Exception('network down'));
    final gateway = await resolveMatrixGatewayUrl(endpoint, httpClient: mock);
    expect(gateway, fallbackMatrixGatewayUrl);
  });
}
