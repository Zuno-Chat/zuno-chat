import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'fake_http.dart';
import 'fake_matrix.dart';

void main() {
  test('an SDK request answered by the fake finishes in fake time', () {
    fakeAsync((async) {
      final client = buildTestClient(
        httpClient: FakeHttpClient(
          (request) async => http.Response(
            jsonEncode({
              'versions': ['v1.11'],
            }),
            200,
          ),
        ),
      )..homeserver = Uri.parse('https://example.org');
      List<String>? versions;

      client.getVersions().then((answer) => versions = answer.versions);
      async.flushMicrotasks();

      expect(versions, ['v1.11']);
    });
  });

  test('the fake hands the handler the request it was sent', () async {
    http.Request? seen;
    final client = FakeHttpClient((request) async {
      seen = request;
      return http.Response('ok', 201);
    });

    final response = await client.post(
      Uri.parse('https://example.org/x'),
      headers: {'x-test': '1'},
      body: 'hello',
    );

    expect(response.statusCode, 201);
    expect(response.body, 'ok');
    expect(seen?.method, 'POST');
    expect(seen?.headers['x-test'], '1');
    expect(seen?.body, 'hello');
  });

  test('a body read only in part still finishes in fake time', () {
    fakeAsync((async) {
      List<int>? first;

      fakeTimeBody([1, 2, 3]).first.then((chunk) => first = chunk);
      async.flushMicrotasks();

      expect(first, [1, 2, 3]);
    });
  });
}
