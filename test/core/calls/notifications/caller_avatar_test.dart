import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/notifications/caller_avatar.dart';

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

  test('returns null when the download exceeds the timeout', () async {
    final result = await fetchCallerAvatarBytes(
      client,
      Uri.parse('mxc://example.org/avatar1'),
      download: (uri) => Future.delayed(
        const Duration(milliseconds: 50),
        () => Uint8List(0),
      ),
      timeout: const Duration(milliseconds: 5),
    );

    expect(result, isNull);
  });
}
