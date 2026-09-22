import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:zuno/core/matrix/attachment_cache.dart';

void main() {
  late Directory dir;
  late DiskAttachmentCache disk;
  final bytes = Uint8List.fromList([1, 2, 3, 4]);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('zuno_attachment_cache');
    disk = DiskAttachmentCache.forTest(dir);
  });

  tearDown(() => dir.deleteSync(recursive: true));

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

  test('a stale entry is dropped', () async {
    final stored = await disk.put('k', bytes);
    await stored!.setLastModified(
      DateTime.now().subtract(const Duration(days: 2)),
    );
    expect(await disk.file('k'), isNull);
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

  test('ten concurrent fetches of one key download once', () async {
    AttachmentCache.instance.clear();
    var fetches = 0;
    final gate = Completer<void>();
    Future<Uint8List> fetch() async {
      fetches++;
      await gate.future;
      return bytes;
    }

    final all = [
      for (var i = 0; i < 10; i++)
        fetchCachedAttachment('dedupe', fetch, disk: disk),
    ];
    await pumpEventQueue();
    gate.complete();

    expect(await Future.wait(all), everyElement(bytes));
    expect(fetches, 1);
  });

  test('ten concurrent avatar fetches download once', () async {
    var fetches = 0;
    final gate = Completer<void>();
    Future<Uint8List> fetch() async {
      fetches++;
      await gate.future;
      return bytes;
    }

    final all = [
      for (var i = 0; i < 10; i++)
        fetchCachedAvatar('avatar:dedupe', fetch, disk: disk),
    ];
    await pumpEventQueue();
    gate.complete();

    expect(await Future.wait(all), everyElement(bytes));
    expect(fetches, 1);
  });

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
}
