import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:zuno/core/matrix/upload_progress_http_client.dart';

void main() {
  test('an upload reports progress chunk by chunk up to 1.0, and its response '
      'passes through', () async {
    final client = UploadProgressHttpClient(
      MockClient(
        (request) async => http.Response(jsonEncode({'ok': true}), 200),
      ),
    );
    addTearDown(client.close);

    final progress = <double>[];
    client.onUploadProgress.listen(progress.add);

    final body = Uint8List.fromList(List.generate(500 * 1024, (i) => i % 256));
    final request = http.Request(
      'POST',
      Uri.parse('https://example.org/_matrix/media/v3/upload'),
    )..bodyBytes = body;

    final response = await http.Response.fromStream(await client.send(request));

    expect(response.statusCode, 200);
    expect(jsonDecode(response.body), {'ok': true});
    expect(progress.length, greaterThan(1));
    expect(progress.any((p) => p > 0.0 && p < 1.0), isTrue);
    expect(progress.last, closeTo(1.0, 0.001));
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
    }
  });

  test(
    'a non-upload request passes through untouched, no progress reported',
    () async {
      final mock = MockClient((request) async {
        expect(request.url.path, '/_matrix/client/v3/sync');
        return http.Response('{}', 200);
      });
      final client = UploadProgressHttpClient(mock);
      addTearDown(client.close);

      var progressFired = false;
      client.onUploadProgress.listen((_) => progressFired = true);

      final response = await client.get(
        Uri.parse('https://example.org/_matrix/client/v3/sync'),
      );

      expect(response.statusCode, 200);
      expect(progressFired, isFalse);
    },
  );

  test('a GET to the upload path (never a real case, but not POST) passes through untouched', () async {
    final mock = MockClient((request) async => http.Response('{}', 200));
    final client = UploadProgressHttpClient(mock);
    addTearDown(client.close);

    var progressFired = false;
    client.onUploadProgress.listen((_) => progressFired = true);

    await client.get(Uri.parse('https://example.org/_matrix/media/v3/upload'));

    expect(progressFired, isFalse);
  });
}
