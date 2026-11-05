import 'dart:convert';
import 'dart:io' show PathNotFoundException;

import 'package:file/file.dart';
import 'package:path/path.dart' as p;

import '../../async/serial_lock.dart';
import '../../errors/caught_errors.dart';
import '../../files/file_system.dart';
import '../../files/unique_name.dart';
import 'notification_ids.dart';
import 'notification_thread.dart';

export 'notification_thread.dart';

const notificationThreadsFileName = 'notification_threads.json';
const maxNotificationThreads = 32;

typedef WaitingLine = ({String roomId, String eventId});

class NotificationThreadStore {
  NotificationThreadStore({Future<Directory> Function()? directory})
    : _directory = directory ?? applicationSupportDirectory;

  static NotificationThreadStore instance = NotificationThreadStore();

  final Future<Directory> Function() _directory;
  final _lock = SerialLock();
  File? _file;

  Future<T> _run<T>(
    String label,
    T fallback,
    Future<T> Function(File file) step,
  ) => _lock.run(() async {
    try {
      final file = _file ??= fileSystem.file(
        p.join((await _directory()).path, notificationThreadsFileName),
      );
      return await step(file);
    } catch (e, s) {
      reportCaught('notification threads $label', e, s);
      return fallback;
    }
  });

  Future<Map<String, Object?>> _readAll(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map ? decoded.cast<String, Object?>() : {};
    } on PathNotFoundException {
      return {};
    } on FormatException {
      return {};
    }
  }

  Future<void> _writeAll(File file, Map<String, Object?> all) async {
    final pending = fileSystem.file('${file.path}.${uniqueName()}');
    try {
      await pending.writeAsString(jsonEncode(all));
      await pending.rename(file.path);
    } catch (_) {
      await _delete(pending);
      rethrow;
    }
  }

  Future<void> _delete(File file) async {
    try {
      await file.delete();
    } on PathNotFoundException {
      return;
    }
  }

  Future<StoredNotificationThread?> read(String key) => _run(
    'read',
    null,
    (file) async =>
        StoredNotificationThread.fromJson(key, (await _readAll(file))[key]),
  );

  Future<Map<String, List<WaitingLine>>> waitingLines() =>
      _run('read', const {}, (file) async {
        final waiting = <String, List<WaitingLine>>{};
        for (final MapEntry(:key, :value) in (await _readAll(file)).entries) {
          final thread = StoredNotificationThread.fromJson(key, value);
          if (thread == null) continue;
          final lines = [
            for (final line in thread.lines)
              if (line.placeholder)
                if (line.eventId case final eventId?)
                  (roomId: thread.roomId, eventId: eventId),
          ];
          if (lines.isNotEmpty) waiting[key] = lines;
        }
        return waiting;
      });

  Future<void> write(
    StoredNotificationThread thread, {
    required Future<Set<int>?> Function() showing,
  }) => _run('write', null, (file) async {
    final ids = await showing();
    final all = await _readAll(file);
    if (ids != null) {
      all.removeWhere((key, _) => !ids.contains(messageNotificationIdFor(key)));
    }
    all
      ..remove(thread.key)
      ..[thread.key] = thread.toJson();
    while (all.length > maxNotificationThreads) {
      all.remove(all.keys.first);
    }
    await _writeAll(file, all);
  });

  Future<void> clear(String key) => _run('clear', null, (file) async {
    final all = await _readAll(file);
    if (all.remove(key) == null) return;
    await _writeAll(file, all);
  });

  Future<void> clearAll() => _run('clear', null, (file) async {
    await _delete(file);
    final leftover = '${file.basename}.';
    await for (final entry in file.parent.list()) {
      if (entry is File && entry.basename.startsWith(leftover)) {
        await _delete(entry);
      }
    }
  });
}
