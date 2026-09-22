import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/notifications/notification_avatar_cache.dart';

void main() {
  late Directory dir;
  late NotificationAvatarCache cache;
  final alice = Uri.parse('mxc://x/alice');

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('avatars');
    addTearDown(() => dir.delete(recursive: true));
    cache = NotificationAvatarCache(directory: () async => dir);
  });

  test('misses for an avatar never stored', () async {
    expect(await cache.read(alice), isNull);
  });

  test('returns what was written, keyed by the avatar url', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    await cache.write(alice, bytes);

    expect(await cache.read(alice), bytes);
    expect(await cache.read(Uri.parse('mxc://x/alice-new')), isNull);
  });

  test('a cache directory that cannot be reached degrades to a miss', () async {
    final broken = NotificationAvatarCache(
      directory: () async => throw const FileSystemException('no'),
    );

    expect(await broken.read(alice), isNull);
    await expectLater(broken.write(alice, Uint8List.fromList([1])), completes);
  });
}
