import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:zuno/core/network/app_http_overrides.dart';
import 'package:zuno/core/push/unified_push/matrix_unified_push_gateway.dart';

import '../../../helpers/caught_reports.dart';

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

  for (final (name, answer) in <(String, Future<http.Response> Function())>[
    ('a non-200 response', () async => http.Response('not found', 404)),
    (
      'an unexpected JSON shape',
      () async => http.Response(jsonEncode({'unrelated': true}), 200),
    ),
    ('malformed JSON', () async => http.Response('not json', 200)),
    ('a request that throws', () async => throw Exception('network down')),
  ]) {
    test('falls back to the public gateway on $name', () async {
      final mock = MockClient((request) => answer());
      final gateway = await resolveMatrixGatewayUrl(endpoint, httpClient: mock);
      expect(gateway, fallbackMatrixGatewayUrl);
    });
  }

  test('an http distributor uses the public gateway without reporting the '
      'refused discovery as a failure', () async {
    final mock = MockClient(
      (request) async => throw CleartextRefusedException(request.url),
    );
    late Uri gateway;

    final reports = await reportsDuring(() async {
      gateway = await resolveMatrixGatewayUrl(
        Uri.parse('http://ntfy.example.org/up/abc123'),
        httpClient: mock,
      );
    });

    expect(gateway, fallbackMatrixGatewayUrl);
    expect(reports, isEmpty);
  });
}
