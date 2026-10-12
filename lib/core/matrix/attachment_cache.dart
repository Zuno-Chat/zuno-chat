import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../errors/best_effort.dart';
import '../errors/caught_errors.dart';

String attachmentCacheKey(Event event, {required bool thumbnail}) =>
    '${event.eventId}:${thumbnail ? 'thumb' : 'full'}';

var _accountGeneration = 0;

void forgetAccountAttachments() {
  _accountGeneration++;
  AttachmentCache.instance.clear();
}

class _AccountForgotten implements Exception {
  const _AccountForgotten();

  @override
  String toString() => 'the account this attachment was fetched for is gone';
}

void _checkAccount(int generation) {
  if (generation != _accountGeneration) throw const _AccountForgotten();
}

void _remember(int generation, String key, Uint8List bytes) {
  if (generation == _accountGeneration) {
    AttachmentCache.instance.put(key, bytes);
  }
}

final _random = Random.secure();

String _uniqueName() => [
  for (var i = 0; i < 16; i++)
    _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
].join();

class AttachmentCache {
  AttachmentCache._();

  static final instance = AttachmentCache._();

  static const _ttl = Duration(hours: 1);
  static const _maxEntries = 60;

  final _entries = <String, _Entry>{};

  Uint8List? get(String key) {
    final entry = _entries[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.storedAt) > _ttl) {
      _entries.remove(key);
      return null;
    }
    _entries.remove(key);
    _entries[key] = entry;
    return entry.bytes;
  }

  void put(String key, Uint8List bytes) {
    _entries.remove(key);
    _entries[key] = _Entry(bytes, DateTime.now());
    if (_entries.length > _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void clear() => _entries.clear();
}

class _Entry {
  final Uint8List bytes;
  final DateTime storedAt;

  _Entry(this.bytes, this.storedAt);
}

typedef _Stored = ({
  FileSystemEntity entity,
  int size,
  DateTime modified,
  bool expires,
  bool budgeted,
});

class DiskAttachmentCache {
  DiskAttachmentCache._() : _pinned = null;
  DiskAttachmentCache.forTest(Directory dir) : _pinned = dir;

  static final instance = DiskAttachmentCache._();

  static const _ttl = Duration(days: 1);
  static const _dirName = 'attachment_cache';
  static const _keptDirName = 'kept';
  static const _handoverDirName = 'handover';
  static const _maxTotalBytes = 256 * 1024 * 1024;
  static const _sweepInterval = Duration(minutes: 5);

  final Directory? _pinned;
  Directory? _located;
  DateTime? _lastSweep;
  Future<void>? _sweepInFlight;

  Future<Directory> _directory() async =>
      _pinned ??
      (_located ??= Directory(
        p.join((await getApplicationCacheDirectory()).path, _dirName),
      ));

  String _fileNameFor(String key) =>
      sha256.convert(utf8.encode(key)).toString().substring(0, 32);

  Future<File> _fileFor(String key, {required bool expires}) async => File(
    p.joinAll([
      (await _directory()).path,
      if (!expires) _keptDirName,
      _fileNameFor(key),
    ]),
  );

  bool _isExpired(DateTime modified) =>
      DateTime.now().difference(modified) > _ttl;

  Future<File?> file(String key, {bool expires = true}) async {
    try {
      final file = await _fileFor(key, expires: expires);
      if (!await file.exists()) return null;
      final modified = (await file.stat()).modified;
      if (expires && _isExpired(modified)) {
        unawaited(_delete(file, label: 'drop an expired attachment'));
        return null;
      }
      unawaited(
        runBestEffort(
          () => file.setLastModified(DateTime.now()),
          label: 'touch a cached attachment',
        ),
      );
      return file;
    } catch (e, s) {
      reportCaught('find a cached attachment', e, s);
      return null;
    }
  }

  Future<Uint8List?> get(String key, {bool expires = true}) async {
    final cached = await file(key, expires: expires);
    if (cached == null) return null;
    try {
      return await cached.readAsBytes();
    } on PathNotFoundException {
      return null;
    } catch (e, s) {
      reportCaught('read a cached attachment', e, s);
      return null;
    }
  }

  Future<File?> put(String key, Uint8List bytes, {bool expires = true}) =>
      _put(_accountGeneration, key, bytes, expires: expires);

  Future<File?> _put(
    int generation,
    String key,
    Uint8List bytes, {
    required bool expires,
  }) async {
    try {
      return await _store(generation, key, bytes, expires: expires);
    } on _AccountForgotten {
      return null;
    } on PathNotFoundException {
      return null;
    } catch (e, s) {
      reportCaught('cache an attachment', e, s);
      return null;
    }
  }

  Future<File> _store(
    int generation,
    String key,
    Uint8List bytes, {
    bool expires = true,
  }) async {
    final file = await _fileFor(key, expires: expires);
    final part = File(
      p.join((await _directory()).path, '${_uniqueName()}.part'),
    );
    try {
      await _writeFor(generation, part, () => part.writeAsBytes(bytes));
      await _writeFor(generation, file, () => part.rename(file.path));
    } catch (_) {
      await _delete(part, label: 'drop a partly cached attachment');
      rethrow;
    }
    _sweepSoon();
    return file;
  }

  Future<File> _handOver(int generation, String name, File source) async {
    final folder = Directory(
      p.join((await _directory()).path, _handoverDirName, _uniqueName()),
    );
    final copy = File(p.join(folder.path, name));
    try {
      await _writeFor(generation, folder, () async {
        await folder.create(recursive: true);
        await source.copy(copy.path);
        await copy.setLastModified(DateTime.now());
      });
    } catch (_) {
      await _delete(folder, label: 'drop a partial hand-over copy');
      rethrow;
    }
    _sweepSoon();
    return copy;
  }

  Future<void> _writeFor(
    int generation,
    FileSystemEntity written,
    Future<void> Function() write,
  ) async {
    _checkAccount(generation);
    try {
      await write();
    } on PathNotFoundException {
      _checkAccount(generation);
      await written.parent.create(recursive: true);
      await write();
    }
    if (generation == _accountGeneration) return;
    await _delete(written, label: 'drop an attachment of a forgotten account');
    throw const _AccountForgotten();
  }

  Future<void> remove(String key, {bool expires = true}) async {
    try {
      await (await _fileFor(key, expires: expires)).delete();
    } on PathNotFoundException {
      return;
    } catch (e, s) {
      reportCaught('remove a cached attachment', e, s);
    }
  }

  Future<bool> _delete(FileSystemEntity entity, {required String label}) async {
    try {
      await entity.delete(recursive: entity is Directory);
      return true;
    } on PathNotFoundException {
      return false;
    } catch (e, s) {
      reportCaught(label, e, s);
      return false;
    }
  }

  Future<void> sweep() => _sweepInFlight ??= _sweep().whenComplete(() {
    _sweepInFlight = null;
    _lastSweep = DateTime.now();
  });

  void _sweepSoon() {
    final last = _lastSweep;
    if (last != null && DateTime.now().difference(last) < _sweepInterval) {
      return;
    }
    unawaited(sweep());
  }

  Future<void> _sweep() async {
    try {
      final dir = await _directory();
      if (!await dir.exists()) return;
      final live = <_Stored>[];
      final oversized = <_Stored>[];
      for (final stored in await _storedIn(dir)) {
        if (stored.expires && _isExpired(stored.modified)) {
          await _delete(stored.entity, label: 'drop an expired attachment');
        } else if (!stored.budgeted) {
          continue;
        } else if (stored.size <= _maxTotalBytes) {
          live.add(stored);
        } else if (stored.expires) {
          oversized.add(stored);
        } else {
          await _delete(stored.entity, label: 'drop an oversized avatar');
        }
      }
      oversized.sort((a, b) => b.modified.compareTo(a.modified));
      for (final stored in oversized.skip(1)) {
        await _delete(stored.entity, label: 'drop an oversized attachment');
      }
      var total = live.fold(0, (sum, stored) => sum + stored.size);
      if (total <= _maxTotalBytes) return;
      live.sort((a, b) => a.modified.compareTo(b.modified));
      for (final stored in live) {
        if (total <= _maxTotalBytes) break;
        if (await _delete(stored.entity, label: 'evict a cached attachment')) {
          total -= stored.size;
        }
      }
    } on PathNotFoundException {
      return;
    } catch (e, s) {
      reportCaught('sweep the attachment cache', e, s);
    }
  }

  Future<List<_Stored>> _storedIn(Directory dir) async {
    final stored = <_Stored>[];
    await for (final entity in dir.list(followLinks: false)) {
      switch ((entity, p.basename(entity.path))) {
        case (File file, _):
          stored.add(await _storedFile(file, expires: true));
        case (Directory kept, _keptDirName):
          await for (final file in kept.list(followLinks: false)) {
            if (file is File) {
              stored.add(await _storedFile(file, expires: false));
            }
          }
        case (Directory handover, _handoverDirName):
          await for (final folder in handover.list(followLinks: false)) {
            if (folder is! Directory) continue;
            if (await _storedFolder(folder) case final held?) stored.add(held);
          }
      }
    }
    return stored;
  }

  Future<_Stored> _storedFile(File file, {required bool expires}) async {
    final stat = await file.stat();
    return (
      entity: file,
      size: stat.size,
      modified: stat.modified,
      expires: expires,
      budgeted: true,
    );
  }

  Future<_Stored?> _storedFolder(Directory folder) async {
    var size = 0;
    DateTime? newest;
    try {
      await for (final file in folder.list(followLinks: false)) {
        final stat = await file.stat();
        size += stat.size;
        if (newest == null || stat.modified.isAfter(newest)) {
          newest = stat.modified;
        }
      }
    } on PathNotFoundException {
      return null;
    }
    return (
      entity: folder,
      size: size,
      modified: newest ?? (await folder.stat()).modified,
      expires: true,
      budgeted: false,
    );
  }

  Future<void> clear() async {
    try {
      final dir = await _directory();
      if (await dir.exists()) await dir.delete(recursive: true);
      _located = null;
    } catch (e, s) {
      reportCaught('clear the attachment cache', e, s);
    }
  }
}

final _inFlight = <(int, String), Future<Uint8List>>{};

Future<Uint8List> _once(
  String key,
  Future<Uint8List> Function(int generation) load,
) {
  final slot = (_accountGeneration, key);
  return _inFlight[slot] ??= load(slot.$1).whenComplete(() {
    _inFlight.remove(slot);
  });
}

Future<Uint8List> fetchCachedAttachment(
  String key,
  Future<Uint8List> Function() fetch, {
  DiskAttachmentCache? disk,
}) {
  final memoryHit = AttachmentCache.instance.get(key);
  if (memoryHit != null) return Future.value(memoryHit);

  return _once(key, (generation) async {
    final cache = disk ?? DiskAttachmentCache.instance;
    final diskHit = await cache.get(key);
    if (diskHit != null) {
      _remember(generation, key, diskHit);
      return diskHit;
    }

    final bytes = await fetch();
    _remember(generation, key, bytes);
    unawaited(cache._put(generation, key, bytes, expires: true));
    return bytes;
  });
}

Future<Uint8List> fetchCachedAvatar(
  String key,
  Future<Uint8List> Function() fetch, {
  DiskAttachmentCache? disk,
}) => _once(key, (generation) async {
  final cache = disk ?? DiskAttachmentCache.instance;
  final diskHit = await cache.get(key, expires: false);
  if (diskHit != null) return diskHit;

  final bytes = await fetch();
  await cache._put(generation, key, bytes, expires: false);
  return bytes;
});

Future<File> _cachedFile(
  int generation,
  DiskAttachmentCache cache,
  String key,
  Future<Uint8List> Function() fetch,
) async =>
    await cache.file(key) ??
    await cache._store(
      generation,
      key,
      AttachmentCache.instance.get(key) ?? await fetch(),
    );

Future<File> fetchCachedAttachmentFile(
  String key,
  Future<Uint8List> Function() fetch, {
  DiskAttachmentCache? disk,
}) => _cachedFile(
  _accountGeneration,
  disk ?? DiskAttachmentCache.instance,
  key,
  fetch,
);

Future<File> fetchAttachmentHandover(
  String key,
  String name,
  Future<Uint8List> Function() fetch, {
  DiskAttachmentCache? disk,
}) async {
  final generation = _accountGeneration;
  final cache = disk ?? DiskAttachmentCache.instance;
  final source = await _cachedFile(generation, cache, key, fetch);
  return cache._handOver(generation, name, source);
}

Future<bool> isAttachmentCached(String key, {DiskAttachmentCache? disk}) async {
  if (AttachmentCache.instance.get(key) != null) return true;
  return await (disk ?? DiskAttachmentCache.instance).file(key) != null;
}
