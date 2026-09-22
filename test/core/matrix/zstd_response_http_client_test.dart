import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:zuno/core/matrix/zstd_response_http_client.dart';

Uint8List _fakeCompress(String plaintext) =>
    Uint8List.fromList(plaintext.codeUnits.reversed.toList());

Future<Uint8List?> _fakeDecompress(Uint8List data) async =>
    Uint8List.fromList(data.reversed.toList());

void main() {
  test('a zstd-encoded response is decompressed and the header stripped', () async {
    final mock = MockClient((request) async {
      return http.Response.bytes(
        _fakeCompress('{"ok":true}'),
        200,
        headers: {'content-encoding': 'zstd'},
      );
    });
    final client = ZstdResponseHttpClient(mock, decompress: _fakeDecompress);
    addTearDown(client.close);

    final response = await client.get(Uri.parse('https://example.org/_matrix/client/v3/sync'));

    expect(response.body, '{"ok":true}');
    expect(response.headers.containsKey('content-encoding'), isFalse);
    expect(response.headers['content-length'], '11');
  });

  test('a response with no content-encoding passes through untouched', () async {
    var decompressCalled = false;
    final mock = MockClient((request) async => http.Response('{"ok":true}', 200));
    final client = ZstdResponseHttpClient(
      mock,
      decompress: (data) async {
        decompressCalled = true;
        return data;
      },
    );
    addTearDown(client.close);

    final response = await client.get(Uri.parse('https://example.org/_matrix/client/v3/sync'));

    expect(response.body, '{"ok":true}');
    expect(decompressCalled, isFalse);
  });

  test('every outgoing request advertises Accept-Encoding: zstd', () async {
    String? seenAcceptEncoding;
    final mock = MockClient((request) async {
      seenAcceptEncoding = request.headers['accept-encoding'];
      return http.Response('{}', 200);
    });
    final client = ZstdResponseHttpClient(mock, decompress: _fakeDecompress);
    addTearDown(client.close);

    await client.get(Uri.parse('https://example.org/_matrix/client/v3/sync'));

    expect(seenAcceptEncoding, 'zstd');
  });

  test('an existing Accept-Encoding header keeps its value and gains zstd', () async {
    String? seenAcceptEncoding;
    final mock = MockClient((request) async {
      seenAcceptEncoding = request.headers['accept-encoding'];
      return http.Response('{}', 200);
    });
    final client = ZstdResponseHttpClient(mock, decompress: _fakeDecompress);
    addTearDown(client.close);

    final request = http.Request(
      'GET',
      Uri.parse('https://example.org/_matrix/client/v3/sync'),
    )..headers['accept-encoding'] = 'gzip';
    await client.send(request);

    expect(seenAcceptEncoding, 'gzip, zstd');
  });

  test('a corrupt zstd response throws instead of returning garbage', () async {
    final mock = MockClient((request) async {
      return http.Response.bytes(
        Uint8List.fromList([1, 2, 3]),
        200,
        headers: {'content-encoding': 'zstd'},
      );
    });
    final client = ZstdResponseHttpClient(
      mock,
      decompress: (data) async => null,
    );
    addTearDown(client.close);

    expect(
      () => client.get(Uri.parse('https://example.org/_matrix/client/v3/sync')),
      throwsA(isA<http.ClientException>()),
    );
  });
}
