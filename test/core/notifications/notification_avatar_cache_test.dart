import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/notifications/notification_avatar_cache.dart';

void main() {
  late Directory dir;
  late NotificationAvatarCache cache;
  late int lookups;
  final alice = Uri.parse('mxc://x/alice');

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('avatars');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    lookups = 0;
    cache = NotificationAvatarCache(
      directory: () async {
        lookups++;
        return dir;
      },
    );
  });

  test('misses for an avatar never stored', () async {
    expect(await cache.read(alice), isNull);
    expect(await cache.contains(alice), isFalse);
  });

  test('returns what was written, keyed by the avatar url', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    await cache.write(alice, bytes);

    expect(await cache.read(alice), bytes);
    expect(await cache.contains(alice), isTrue);
    expect(await cache.read(Uri.parse('mxc://x/alice-new')), isNull);
  });

  test('finds its directory once, however often it is used', () async {
    await cache.read(alice);
    await cache.write(alice, Uint8List.fromList([1]));
    await cache.read(alice);
    await cache.contains(alice);

    expect(lookups, 1);
  });

  test('a directory that could not be found is looked for again next '
      'time', () async {
    var attempts = 0;
    final flaky = NotificationAvatarCache(
      directory: () async {
        if (attempts++ == 0) throw const FileSystemException('not yet');
        return dir;
      },
    );

    expect(await flaky.read(alice), isNull);
    await flaky.write(alice, Uint8List.fromList([4]));

    expect(await flaky.read(alice), Uint8List.fromList([4]));
  });

  test('a directory removed underneath it is made again on the next '
      'write', () async {
    await cache.write(alice, Uint8List.fromList([1]));
    await dir.delete(recursive: true);

    await cache.write(alice, Uint8List.fromList([2]));

    expect(await cache.read(alice), Uint8List.fromList([2]));
  });

  test('a cache directory that cannot be reached degrades to a miss', () async {
    final broken = NotificationAvatarCache(
      directory: () async => throw const FileSystemException('no'),
    );

    expect(await broken.read(alice), isNull);
    expect(await broken.contains(alice), isFalse);
    await expectLater(broken.write(alice, Uint8List.fromList([1])), completes);
  });
}
