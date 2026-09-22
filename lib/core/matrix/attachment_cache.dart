import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

String attachmentCacheKey(Event event, {required bool thumbnail}) =>
    '${event.eventId}:${thumbnail ? 'thumb' : 'full'}';

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

class DiskAttachmentCache {
  DiskAttachmentCache._();
  DiskAttachmentCache.forTest(Directory dir) : _dir = dir;

  static final instance = DiskAttachmentCache._();

  static const _ttl = Duration(days: 1);
  static const _dirName = 'attachment_cache';
  static const _maxTotalBytes = 256 * 1024 * 1024;
  static const _sweepInterval = Duration(minutes: 5);

  Directory? _dir;
  DateTime? _lastSweep;
  Future<void>? _sweepInFlight;

  Future<Directory> _directory() async {
    final existing = _dir;
    if (existing != null) return existing;
    final cacheDir = await getApplicationCacheDirectory();
    final dir = Directory(p.join(cacheDir.path, _dirName));
    await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  String _fileNameFor(String key) =>
      sha256.convert(utf8.encode(key)).toString().substring(0, 32);

  Future<File?> file(String key, {bool expires = true}) async {
    try {
      final dir = await _directory();
      final file = File(p.join(dir.path, _fileNameFor(key)));
      if (!await file.exists()) return null;
      final modified = (await file.stat()).modified;
      if (expires && DateTime.now().difference(modified) > _ttl) {
        file.delete().ignore();
        return null;
      }
      unawaited(file.setLastModified(DateTime.now()).catchError((_) {}));
      return file;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> get(String key, {bool expires = true}) async {
    final cached = await file(key, expires: expires);
    if (cached == null) return null;
    try {
      return await cached.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<File?> put(String key, Uint8List bytes) async {
    try {
      final dir = await _directory();
      final file = await File(p.join(dir.path, _fileNameFor(key)))
          .writeAsBytes(bytes);
      unawaited(_enforceBudget());
      return file;
    } catch (_) {
      return null;
    }
  }

  Future<void> remove(String key) async {
    try {
      final dir = await _directory();
      await File(p.join(dir.path, _fileNameFor(key))).delete();
    } catch (_) {}
  }

  Future<void> _enforceBudget() {
    final last = _lastSweep;
    if (last != null && DateTime.now().difference(last) < _sweepInterval) {
      return Future.value();
    }
    return _sweepInFlight ??= _sweep().whenComplete(() {
      _sweepInFlight = null;
      _lastSweep = DateTime.now();
    });
  }

  Future<void> _sweep() async {
    try {
      final dir = await _directory();
      final entries = <({File file, int size, DateTime modified})>[];
      var total = 0;
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        entries.add((file: entity, size: stat.size, modified: stat.modified));
        total += stat.size;
      }
      if (total <= _maxTotalBytes) return;
      entries.sort((a, b) => a.modified.compareTo(b.modified));
      for (final entry in entries) {
        if (total <= _maxTotalBytes) break;
        try {
          await entry.file.delete();
          total -= entry.size;
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      final dir = await _directory();
      if (await dir.exists()) await dir.delete(recursive: true);
      _dir = null;
    } catch (_) {}
  }
}

final _inFlight = <String, Future<Uint8List>>{};

Future<Uint8List> _once(String key, Future<Uint8List> Function() load) =>
    _inFlight[key] ??= load().whenComplete(() {
      _inFlight.remove(key);
    });

Future<Uint8List> fetchCachedAttachment(
  String key,
  Future<Uint8List> Function() fetch, {
  DiskAttachmentCache? disk,
}) {
  final memoryHit = AttachmentCache.instance.get(key);
  if (memoryHit != null) return Future.value(memoryHit);

  return _once(key, () async {
    final cache = disk ?? DiskAttachmentCache.instance;
    final diskHit = await cache.get(key);
    if (diskHit != null) {
      AttachmentCache.instance.put(key, diskHit);
      return diskHit;
    }

    final bytes = await fetch();
    AttachmentCache.instance.put(key, bytes);
    unawaited(cache.put(key, bytes));
    return bytes;
  });
}

Future<Uint8List> fetchCachedAvatar(
  String key,
  Future<Uint8List> Function() fetch, {
  DiskAttachmentCache? disk,
}) => _once(key, () async {
  final cache = disk ?? DiskAttachmentCache.instance;
  final diskHit = await cache.get(key, expires: false);
  if (diskHit != null) return diskHit;

  final bytes = await fetch();
  await cache.put(key, bytes);
  return bytes;
});

Future<File> fetchCachedAttachmentFile(
  String key,
  Future<Uint8List> Function() fetch, {
  DiskAttachmentCache? disk,
}) async {
  final cache = disk ?? DiskAttachmentCache.instance;
  final hit = await cache.file(key);
  if (hit != null) return hit;
  final bytes = await fetch();
  final stored = await cache.put(key, bytes);
  if (stored != null) return stored;
  final dir = await getTemporaryDirectory();
  return File(
    p.join(dir.path, 'attachment_${DateTime.now().microsecondsSinceEpoch}'),
  ).writeAsBytes(bytes);
}

Future<bool> isAttachmentCached(String key, {DiskAttachmentCache? disk}) async {
  if (AttachmentCache.instance.get(key) != null) return true;
  return await (disk ?? DiskAttachmentCache.instance).file(key) != null;
}
