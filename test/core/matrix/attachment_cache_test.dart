import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:zuno/core/matrix/attachment_cache.dart';

import '../../helpers/caught_reports.dart';
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

  File grow(File file, {required int megabytes, DateTime? modified}) {
    file.openSync(mode: FileMode.write)
      ..setPositionSync(megabytes * 1024 * 1024 - 1)
      ..writeByteSync(0)
      ..closeSync();
    if (modified != null) file.setLastModifiedSync(modified);
    return file;
  }

  File sparseFile(String name, {required int megabytes, DateTime? modified}) =>
      grow(File('${dir.path}/$name'), megabytes: megabytes, modified: modified);

  List<File> filesOnDisk() => dir.existsSync()
      ? dir.listSync(recursive: true).whereType<File>().toList()
      : [];

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> untilStored(
    DiskAttachmentCache cache,
    String key, {
    bool expires = true,
  }) async {
    for (var i = 0; i < 100; i++) {
      if (await cache.file(key, expires: expires) != null) return;
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
      await untilStored(disk, '$kind:dedupe', expires: kind != 'avatar');
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
      final avatar = await disk.put('avatar:old', bytes, expires: false);
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

  test(
    'storing an entry again never changes a copy a reader has open',
    () async {
      final first = await disk.put('k', bytes);
      final reader = await first!.open();
      addTearDown(reader.close);

      await disk.put('k', Uint8List.fromList([9]));

      expect(await reader.read(bytes.length), bytes);
      expect(await disk.get('k'), [9]);
    },
  );

  test('a stored entry leaves no partial copy behind', () async {
    await disk.put('k', bytes);
    await disk.put('avatar', bytes, expires: false);
    await fetchCachedAttachmentFile('file', () async => bytes, disk: disk);

    expect(filesOnDisk(), hasLength(3));
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

    test('a hand-over copy is made from a hit without fetching', () async {
      AttachmentCache.instance.put('k', bytes);
      var fetches = 0;

      final copy = await fetchAttachmentHandover('k', 'a.bin', () async {
        fetches++;
        return Uint8List(0);
      }, disk: disk);

      expect(copy.readAsBytesSync(), bytes);
      expect(fetches, 0);
    });

    test('a disk hit is kept in memory for next time', () async {
      await disk.put('k', bytes);

      await fetchCachedAttachment('k', () async => Uint8List(0), disk: disk);

      expect(AttachmentCache.instance.get('k'), bytes);
    });
  });

  group('disk budget', () {
    final hourAgo = DateTime.now().subtract(const Duration(hours: 1));
    final twoHoursAgo = DateTime.now().subtract(const Duration(hours: 2));

    test('trims the oldest files once the cache passes 256 MiB', () async {
      final old = sparseFile('old', megabytes: 150, modified: twoHoursAgo);
      final newer = sparseFile('newer', megabytes: 150, modified: hourAgo);

      final fresh = await disk.put('fresh', bytes);
      await until(() => !old.existsSync());

      expect(old.existsSync(), isFalse);
      expect(newer.existsSync(), isTrue);
      expect(fresh!.existsSync(), isTrue);
    });

    test(
      'keeps a file larger than all of 256 MiB until it is a day old',
      () async {
        final huge = sparseFile('huge', megabytes: 300);
        final stale = sparseFile(
          'stale',
          megabytes: 300,
          modified: DateTime.now().subtract(const Duration(days: 2)),
        );

        await disk.sweep();

        expect(huge.existsSync(), isTrue);
        expect(stale.existsSync(), isFalse);
      },
    );

    test('of several files larger than all of 256 MiB, keeps only the one used '
        'last', () async {
      final seeding = DiskAttachmentCache.forTest(dir);
      final copy = await fetchAttachmentHandover(
        'shared',
        'clip.mp4',
        () async => bytes,
        disk: seeding,
      );
      grow(copy, megabytes: 300);
      final oldest = sparseFile(
        'oldest',
        megabytes: 300,
        modified: twoHoursAgo,
      );
      final older = sparseFile('older', megabytes: 300, modified: hourAgo);
      final latest = sparseFile(
        'latest',
        megabytes: 300,
        modified: DateTime.now().subtract(const Duration(minutes: 1)),
      );

      await disk.sweep();

      expect(oldest.existsSync(), isFalse);
      expect(older.existsSync(), isFalse);
      expect(latest.existsSync(), isTrue);
      expect(copy.existsSync(), isTrue);
    });

    test(
      'a file larger than all of 256 MiB pushes no other entry out',
      () async {
        final seeding = DiskAttachmentCache.forTest(dir);
        final avatar = await seeding.put('avatar', bytes, expires: false);
        avatar!.setLastModifiedSync(twoHoursAgo);
        final cached = sparseFile('cached', megabytes: 100, modified: hourAgo);
        final huge = sparseFile('huge', megabytes: 300);

        await disk.sweep();

        expect(avatar.existsSync(), isTrue);
        expect(cached.existsSync(), isTrue);
        expect(huge.existsSync(), isTrue);
      },
    );

    test('avatars count against it, the oldest going first', () async {
      final seeding = DiskAttachmentCache.forTest(dir);
      final avatar = await seeding.put('avatar', bytes, expires: false);
      grow(avatar!, megabytes: 150, modified: twoHoursAgo);
      final newer = sparseFile('newer', megabytes: 150, modified: hourAgo);

      await disk.put('fresh', bytes);
      await until(() => !avatar.existsSync());

      expect(avatar.existsSync(), isFalse);
      expect(newer.existsSync(), isTrue);
    });

    test(
      'an avatar larger than all of 256 MiB goes on the next write, alone',
      () async {
        final seeding = DiskAttachmentCache.forTest(dir);
        final avatar = await seeding.put('avatar', bytes, expires: false);
        grow(avatar!, megabytes: 300, modified: hourAgo);
        final cached = sparseFile(
          'cached',
          megabytes: 100,
          modified: twoHoursAgo,
        );

        await disk.put('fresh', bytes);
        await until(() => !avatar.existsSync());

        expect(avatar.existsSync(), isFalse);
        expect(cached.existsSync(), isTrue);
      },
    );

    test('leaves a cache under 256 MiB alone', () async {
      final big = sparseFile('big', megabytes: 200);

      await disk.put('fresh', bytes);
      await until(() => !big.existsSync());

      expect(big.existsSync(), isTrue);
    });

    test(
      'never evicts a hand-over copy, nor counts it against the cache',
      () async {
        final seeding = DiskAttachmentCache.forTest(dir);
        final copy = await fetchAttachmentHandover(
          'shared',
          'clip.mp4',
          () async => bytes,
          disk: seeding,
        );
        grow(copy, megabytes: 300, modified: hourAgo);
        final cached = sparseFile(
          'cached',
          megabytes: 200,
          modified: twoHoursAgo,
        );

        await disk.put('fresh', bytes);
        await until(() => !copy.existsSync() || !cached.existsSync());

        expect(copy.existsSync(), isTrue);
        expect(cached.existsSync(), isTrue);
      },
    );

    test('checks the budget at most every five minutes', () async {
      final first = sparseFile('first', megabytes: 150, modified: hourAgo);
      sparseFile('newer', megabytes: 150);
      await disk.put('a', bytes);
      await disk.sweep();
      expect(first.existsSync(), isFalse);

      final second = sparseFile('second', megabytes: 150, modified: hourAgo);
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
      await untilStored(DiskAttachmentCache.instance, 'k');

      final file = await DiskAttachmentCache.instance.file('k');

      expect(
        file!.parent.path,
        '${server.cacheDirectory.path}/attachment_cache',
      );
    });

    test('serves avatars and attachment files too', () async {
      await fetchCachedAvatar('avatar:k', fetch);
      final file = await fetchCachedAttachmentFile('k', fetch);

      expect(
        await DiskAttachmentCache.instance.get('avatar:k', expires: false),
        bytes,
      );
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

    test(
      'an attachment the cache cannot store is written nowhere else',
      () async {
        final blocked = File('${dir.path}/blocked')..writeAsStringSync('');
        final broken = DiskAttachmentCache.forTest(Directory(blocked.path));

        await expectLater(
          fetchCachedAttachmentFile('k', fetch, disk: broken),
          throwsA(isA<FileSystemException>()),
        );
        expect(server.temporaryDirectory.listSync(), isEmpty);
      },
    );

    test('clearing it deletes hand-over copies too', () async {
      final copy = await fetchAttachmentHandover('k', 'photo.png', fetch);

      await DiskAttachmentCache.instance.clear();

      expect(copy.existsSync(), isFalse);
    });
  });

  test('a cache folder deleted from under it is made again on write', () async {
    await disk.put('before', bytes);
    dir.deleteSync(recursive: true);

    final stored = await disk.put('after', bytes);
    final file = await fetchCachedAttachmentFile(
      'file',
      () async => bytes,
      disk: disk,
    );

    expect(stored!.existsSync(), isTrue);
    expect(file.parent.path, dir.path);
    expect(await file.readAsBytes(), bytes);
  });

  test(
    'a cache given its own folder keeps writing there once cleared',
    () async {
      await disk.put('before', bytes);
      await disk.clear();

      final stored = await disk.put('after', bytes);

      expect(stored, isNotNull);
      expect(p.isWithin(dir.path, stored!.path), isTrue);
      expect(await disk.get('after'), bytes);
    },
  );

  group('hand-over copies', () {
    Future<Uint8List> fetch() async => bytes;

    test('carry the given name inside the cache', () async {
      final copy = await fetchAttachmentHandover(
        'k',
        'holiday.png',
        fetch,
        disk: disk,
      );

      expect(p.basename(copy.path), 'holiday.png');
      expect(p.isWithin(dir.path, copy.path), isTrue);
      expect(await copy.readAsBytes(), bytes);
    });

    test('of two attachments with one name are kept apart', () async {
      final first = await fetchAttachmentHandover(
        'a',
        'photo.jpg',
        fetch,
        disk: disk,
      );
      final second = await fetchAttachmentHandover(
        'b',
        'photo.jpg',
        fetch,
        disk: disk,
      );

      expect(first.path, isNot(second.path));
      expect(first.existsSync() && second.existsSync(), isTrue);
    });

    test(
      'are made afresh each time, so removing one leaves the rest',
      () async {
        final shared = await fetchAttachmentHandover(
          'k',
          'clip.mp4',
          fetch,
          disk: disk,
        );
        final saved = await fetchAttachmentHandover(
          'k',
          'clip.mp4',
          fetch,
          disk: disk,
        );
        await saved.parent.delete(recursive: true);

        expect(p.basename(shared.path), 'clip.mp4');
        expect(shared.path, isNot(saved.path));
        expect(await shared.readAsBytes(), bytes);
      },
    );

    test(
      'reuse the cached attachment instead of downloading it again',
      () async {
        var fetches = 0;
        Future<Uint8List> counted() async {
          fetches++;
          return bytes;
        }

        await fetchCachedAttachmentFile('k', counted, disk: disk);
        await fetchAttachmentHandover('k', 'photo.png', counted, disk: disk);

        expect(fetches, 1);
      },
    );
  });

  group('expiry sweep', () {
    final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));

    test('a sweep clears out attachments unused for a day', () async {
      final seeding = DiskAttachmentCache.forTest(dir);
      final stale = await seeding.put('stale', bytes);
      final fresh = await seeding.put('fresh', bytes);
      stale!.setLastModifiedSync(twoDaysAgo);

      await disk.sweep();

      expect(stale.existsSync(), isFalse);
      expect(fresh!.existsSync(), isTrue);
    });

    test('avatars outlive it', () async {
      final seeding = DiskAttachmentCache.forTest(dir);
      final avatar = await seeding.put('avatar', bytes, expires: false);
      final stale = await seeding.put('stale', bytes);
      avatar!.setLastModifiedSync(twoDaysAgo);
      stale!.setLastModifiedSync(twoDaysAgo);

      await disk.sweep();

      expect(stale.existsSync(), isFalse);
      expect(avatar.existsSync(), isTrue);
      expect(await disk.get('avatar', expires: false), bytes);
    });

    test('hand-over copies go a day after they were made', () async {
      final seeding = DiskAttachmentCache.forTest(dir);
      final stale = await fetchAttachmentHandover(
        'stale',
        'old.png',
        () async => bytes,
        disk: seeding,
      );
      final fresh = await fetchAttachmentHandover(
        'fresh',
        'new.png',
        () async => bytes,
        disk: seeding,
      );
      stale.setLastModifiedSync(twoDaysAgo);

      await disk.sweep();

      expect(stale.parent.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
    });

    test(
      'a lookup leaves every other entry alone, stale or over budget',
      () async {
        final stale = sparseFile('stale', megabytes: 1, modified: twoDaysAgo);
        final big = sparseFile(
          'big',
          megabytes: 150,
          modified: DateTime.now().subtract(const Duration(hours: 1)),
        );
        sparseFile('bigger', megabytes: 150);

        await disk.file('anything');
        await until(() => !stale.existsSync() || !big.existsSync());

        expect(stale.existsSync(), isTrue);
        expect(big.existsSync(), isTrue);
      },
    );

    test(
      'a hand-over copy removed as the sweep reaches it stops nothing else',
      () async {
        final stale = sparseFile('stale', megabytes: 1, modified: twoDaysAgo);
        final copy = File(p.join(dir.path, 'handover', 'saved', 'clip.mp4'))
          ..createSync(recursive: true);
        final vanishing = DiskAttachmentCache.forTest(
          _Listing(
            dir,
            (entry) => p.basename(entry.path) == 'handover'
                ? _Listing(
                    entry as Directory,
                    (folder) => _Listing(
                      folder as Directory,
                      (file) => file,
                      first: () => folder.deleteSync(recursive: true),
                    ),
                  )
                : entry,
          ),
        );

        final reports = await reportsDuring(vanishing.sweep);

        expect(stale.existsSync(), isFalse);
        expect(copy.existsSync(), isFalse);
        expect(reports, isEmpty);
      },
    );
  });

  group('once the account is forgotten', () {
    late Completer<void> gate;

    Future<Uint8List> gated() async {
      await gate.future;
      return bytes;
    }

    setUp(() => gate = Completer<void>());

    test('an avatar it was downloading is not kept', () async {
      final fetching = fetchCachedAvatar('avatar:k', gated, disk: disk);
      await pumpEventQueue();

      forgetAccountAttachments();
      gate.complete();

      expect(await fetching, bytes);
      expect(filesOnDisk(), isEmpty);
    });

    test('an attachment it was downloading is kept nowhere', () async {
      final fetching = fetchCachedAttachment('k', gated, disk: disk);
      await pumpEventQueue();

      forgetAccountAttachments();
      gate.complete();

      expect(await fetching, bytes);
      await pumpEventQueue();
      expect(AttachmentCache.instance.get('k'), isNull);
      expect(filesOnDisk(), isEmpty);
    });

    test(
      'a file or hand-over copy it was downloading is never written',
      () async {
        final file = fetchCachedAttachmentFile('file', gated, disk: disk);
        final copy = fetchAttachmentHandover(
          'copy',
          'clip.mp4',
          gated,
          disk: disk,
        );
        await pumpEventQueue();

        forgetAccountAttachments();
        gate.complete();

        await Future.wait([
          expectLater(file, throwsException),
          expectLater(copy, throwsException),
        ]);
        expect(dir.listSync(recursive: true), isEmpty);
      },
    );

    test('a later fetch never joins the forgotten download', () async {
      final forgotten = fetchCachedAttachment('k', gated, disk: disk);
      await pumpEventQueue();

      forgetAccountAttachments();
      final later = fetchCachedAttachment(
        'k',
        () async => Uint8List.fromList([9]),
        disk: disk,
      );
      gate.complete();

      expect(await later, [9]);
      expect(await forgotten, bytes);
    });

    test('it forgets what is already in memory', () {
      AttachmentCache.instance.put('k', bytes);

      forgetAccountAttachments();

      expect(AttachmentCache.instance.get('k'), isNull);
    });

    test('what is fetched afterwards is kept as usual', () async {
      forgetAccountAttachments();

      await fetchCachedAvatar('avatar:k', () async => bytes, disk: disk);

      expect(await disk.get('avatar:k', expires: false), bytes);
    });
  });
}

class _Listing implements Directory {
  _Listing(this._real, this._entry, {this.first});

  final Directory _real;
  final FileSystemEntity Function(FileSystemEntity) _entry;
  final void Function()? first;

  @override
  String get path => _real.path;

  @override
  Future<bool> exists() => _real.exists();

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) {
    first?.call();
    return _real
        .list(recursive: recursive, followLinks: followLinks)
        .map(_entry);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
