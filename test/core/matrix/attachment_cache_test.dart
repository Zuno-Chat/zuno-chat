import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/attachment_cache.dart';

import '../../helpers/fake_attachments.dart';

void main() {
  late Directory dir;
  late DiskAttachmentCache disk;
  final bytes = Uint8List.fromList([1, 2, 3, 4]);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('zuno_attachment_cache');
    disk = DiskAttachmentCache.forTest(dir);
  });

  tearDown(() {
    AttachmentCache.instance.clear();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File sparseFile(String name, {required int megabytes, DateTime? modified}) {
    final file = File('${dir.path}/$name');
    file.openSync(mode: FileMode.write)
      ..setPositionSync(megabytes * 1024 * 1024 - 1)
      ..writeByteSync(0)
      ..closeSync();
    if (modified != null) file.setLastModifiedSync(modified);
    return file;
  }

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('a miss is null', () async {
    expect(await disk.file('missing'), isNull);
    expect(await disk.get('missing'), isNull);
  });

  test('put then file returns the stored file with the bytes', () async {
    final stored = await disk.put('k', bytes);
    final found = await disk.file('k');
    expect(found!.path, stored!.path);
    expect(await found.readAsBytes(), bytes);
    expect(await disk.get('k'), bytes);
  });

  test('two readers of a stale entry raise no delete error', () async {
    final stored = await disk.put('k', bytes);
    await stored!.setLastModified(
      DateTime.now().subtract(const Duration(days: 2)),
    );
    expect(await Future.wait([disk.file('k'), disk.file('k')]), [null, null]);
    await pumpEventQueue();
  });

  test(
    'fetchCachedAttachmentFile downloads once, then serves from disk',
    () async {
      var fetches = 0;
      Future<Uint8List> fetch() async {
        fetches++;
        return bytes;
      }

      final first = await fetchCachedAttachmentFile('k', fetch, disk: disk);
      final second = await fetchCachedAttachmentFile('k', fetch, disk: disk);
      expect(fetches, 1);
      expect(second.path, first.path);
      expect(await second.readAsBytes(), bytes);
    },
  );

  test('isAttachmentCached reflects the disk', () async {
    expect(await isAttachmentCached('k', disk: disk), isFalse);
    await disk.put('k', bytes);
    expect(await isAttachmentCached('k', disk: disk), isTrue);
  });

  for (final (kind, fetchOnce) in [
    ('attachment', fetchCachedAttachment),
    ('avatar', fetchCachedAvatar),
  ]) {
    test('ten concurrent $kind fetches of one key download once', () async {
      var fetches = 0;
      final gate = Completer<void>();
      Future<Uint8List> fetch() async {
        fetches++;
        await gate.future;
        return bytes;
      }

      final all = [
        for (var i = 0; i < 10; i++)
          fetchOnce('$kind:dedupe', fetch, disk: disk),
      ];
      await pumpEventQueue();
      gate.complete();

      expect(await Future.wait(all), everyElement(bytes));
      expect(fetches, 1);
      await until(() => dir.listSync().isNotEmpty);
    });
  }

  test('a failed fetch is not remembered', () async {
    var fetches = 0;
    Future<Uint8List> fetch() async {
      fetches++;
      if (fetches == 1) throw Exception('offline');
      return bytes;
    }

    await expectLater(
      fetchCachedAvatar('avatar:flaky', fetch, disk: disk),
      throwsException,
    );
    expect(await fetchCachedAvatar('avatar:flaky', fetch, disk: disk), bytes);
    expect(fetches, 2);
  });

  test(
    'a two-day-old avatar is served; a two-day-old attachment is not',
    () async {
      final avatar = await disk.put('avatar:old', bytes);
      final attachment = await disk.put('attachment:old', bytes);
      final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
      await avatar!.setLastModified(twoDaysAgo);
      await attachment!.setLastModified(twoDaysAgo);

      var fetches = 0;
      Future<Uint8List> fetch() async {
        fetches++;
        return Uint8List.fromList([9]);
      }

      expect(await fetchCachedAvatar('avatar:old', fetch, disk: disk), bytes);
      expect(fetches, 0);
      expect(await disk.get('attachment:old'), isNull);
    },
  );

  test('an avatar is on disk by the time its fetch returns', () async {
    await fetchCachedAvatar('avatar:stored', () async => bytes, disk: disk);

    expect(await disk.get('avatar:stored', expires: false), bytes);
  });

  test('remove deletes an entry and tolerates a missing one', () async {
    await disk.put('k', bytes);
    await disk.remove('k');
    await disk.remove('k');

    expect(await disk.get('k'), isNull);
  });

  test('the key tells a thumbnail from the full attachment', () {
    final server = installAttachmentServer();
    final event = server.attachment(eventId: r'$e1');

    expect(attachmentCacheKey(event, thumbnail: true), r'$e1:thumb');
    expect(attachmentCacheKey(event, thumbnail: false), r'$e1:full');
  });

  group('memory cache', () {
    setUp(AttachmentCache.instance.clear);

    Uint8List entry(int i) => Uint8List.fromList([i]);

    test('keeps the 60 most recent entries', () {
      for (var i = 0; i <= 60; i++) {
        AttachmentCache.instance.put('k$i', entry(i));
      }

      expect(AttachmentCache.instance.get('k0'), isNull);
      expect(AttachmentCache.instance.get('k1'), entry(1));
      expect(AttachmentCache.instance.get('k60'), entry(60));
    });

    test('a read keeps an entry from being the next one dropped', () {
      for (var i = 0; i < 60; i++) {
        AttachmentCache.instance.put('k$i', entry(i));
      }

      AttachmentCache.instance.get('k0');
      AttachmentCache.instance.put('k60', entry(60));

      expect(AttachmentCache.instance.get('k0'), entry(0));
      expect(AttachmentCache.instance.get('k1'), isNull);
    });

    test('a hit is served without fetching', () async {
      AttachmentCache.instance.put('k', bytes);
      var fetches = 0;

      final served = await fetchCachedAttachment('k', () async {
        fetches++;
        return Uint8List(0);
      }, disk: disk);

      expect(served, bytes);
      expect(fetches, 0);
    });

    test('a disk hit is kept in memory for next time', () async {
      await disk.put('k', bytes);

      await fetchCachedAttachment('k', () async => Uint8List(0), disk: disk);

      expect(AttachmentCache.instance.get('k'), bytes);
    });
  });

  group('disk budget', () {
    test('trims the oldest files once the cache passes 256 MiB', () async {
      final old = sparseFile(
        'old',
        megabytes: 300,
        modified: DateTime.now().subtract(const Duration(hours: 1)),
      );

      final fresh = await disk.put('fresh', bytes);
      await until(() => !old.existsSync());

      expect(old.existsSync(), isFalse);
      expect(fresh!.existsSync(), isTrue);
    });

    test('leaves a cache under 256 MiB alone', () async {
      final big = sparseFile('big', megabytes: 200);

      await disk.put('fresh', bytes);
      await until(() => !big.existsSync());

      expect(big.existsSync(), isTrue);
    });

    test('checks the budget at most every five minutes', () async {
      final first = sparseFile('first', megabytes: 300);
      await disk.put('a', bytes);
      await until(() => !first.existsSync());
      await pumpEventQueue();

      final second = sparseFile('second', megabytes: 300);
      await disk.put('b', bytes);
      await until(() => !second.existsSync());

      expect(second.existsSync(), isTrue);
    });
  });

  group('shared disk cache', () {
    late AttachmentServer server;

    setUp(() => server = installAttachmentServer());

    Future<Uint8List> fetch() async => bytes;

    test('lives in the app cache directory', () async {
      await fetchCachedAttachment('k', fetch);
      AttachmentCache.instance.clear();
      final directory = Directory(
        '${server.cacheDirectory.path}/attachment_cache',
      );
      await until(
        () => directory.existsSync() && directory.listSync().isNotEmpty,
      );

      final file = await DiskAttachmentCache.instance.file('k');

      expect(
        file!.parent.path,
        '${server.cacheDirectory.path}/attachment_cache',
      );
    });

    test('serves avatars and attachment files too', () async {
      await fetchCachedAvatar('avatar:k', fetch);
      final file = await fetchCachedAttachmentFile('k', fetch);

      expect(await DiskAttachmentCache.instance.get('avatar:k'), bytes);
      expect(await file.readAsBytes(), bytes);
    });

    test('clearing it deletes every cached file', () async {
      await fetchCachedAttachmentFile('k', fetch);

      await DiskAttachmentCache.instance.clear();

      expect(
        Directory('${server.cacheDirectory.path}/attachment_cache')
            .existsSync(),
        isFalse,
      );
      expect(await DiskAttachmentCache.instance.get('k'), isNull);
    });

    test('an attachment the cache cannot store is still handed over', () async {
      final broken = DiskAttachmentCache.forTest(
        Directory('${dir.path}/missing/deeper'),
      );

      final file = await fetchCachedAttachmentFile('k', fetch, disk: broken);

      expect(file.parent.path, server.temporaryDirectory.path);
      expect(await file.readAsBytes(), bytes);
    });
  });
}
