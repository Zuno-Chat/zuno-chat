import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/notifications/caller_avatar.dart';

import '../../../helpers/caught_reports.dart';
import '../../../helpers/fake_matrix.dart';

void main() {
  late Client client;

  setUp(() {
    client = buildTestClient(userId: '@me:example.org');
  });

  test('returns null when there is no avatar url', () async {
    final result = await fetchCallerAvatarBytes(client, null);
    expect(result, isNull);
  });

  test('returns the downloaded bytes on success', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);

    final result = await fetchCallerAvatarBytes(
      client,
      Uri.parse('mxc://example.org/avatar1'),
      download: (uri) async => bytes,
    );

    expect(result, bytes);
  });

  test('returns null when the download throws', () async {
    final result = await fetchCallerAvatarBytes(
      client,
      Uri.parse('mxc://example.org/avatar1'),
      download: (uri) async => throw Exception('offline'),
    );

    expect(result, isNull);
  });

  group('from the homeserver', () {
    late List<String> logs;

    setUp(() => logs = recordDebugPrints());

    Future<Uint8List?> avatarAnswering(http.Response thumbnail) {
      final served = buildTestClient(
        userId: '@me:example.org',
        database: MediaCapableFakeDatabaseApi(),
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/versions')) {
            return http.Response(
              jsonEncode({
                'versions': ['v1.11'],
              }),
              200,
            );
          }
          return thumbnail;
        }),
      );
      served.homeserver = Uri.parse('https://example.org');
      served.accessToken = 'token';
      return fetchCallerAvatarBytes(
        served,
        Uri.parse('mxc://example.org/avatar1'),
      );
    }

    test('an avatar it serves comes back', () async {
      final result = await avatarAnswering(http.Response.bytes([1, 2, 3], 200));

      expect(result, [1, 2, 3]);
      expect(logs, isEmpty);
    });

    test('an avatar it no longer has is none, and nothing to report', () async {
      final result = await avatarAnswering(
        http.Response(jsonEncode({'errcode': 'M_NOT_FOUND'}), 404),
      );

      expect(result, isNull);
      expect(logs, isEmpty);
    });

    test('an avatar it fails to serve is reported', () async {
      final result = await avatarAnswering(http.Response('', 500));

      expect(result, isNull);
      expect(logs, [startsWith('zuno/caught: fetch the caller avatar:')]);
    });
  });

  test('returns null when the download exceeds the timeout', () {
    fakeAsync((async) {
      Object? result = 'unset';
      fetchCallerAvatarBytes(
        client,
        Uri.parse('mxc://example.org/avatar1'),
        download: (uri) => Completer<Uint8List>().future,
      ).then((bytes) => result = bytes);

      async.elapse(callerAvatarTimeout);

      expect(result, isNull);
    });
  });
}
