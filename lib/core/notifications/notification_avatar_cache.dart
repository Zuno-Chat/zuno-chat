import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class NotificationAvatarCache {
  NotificationAvatarCache({Future<Directory> Function()? directory})
    : _directory = directory ?? _defaultDirectory;

  static NotificationAvatarCache instance = NotificationAvatarCache();

  final Future<Directory> Function() _directory;

  static Future<Directory> _defaultDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'notification_avatars'));
  }

  Future<File?> _fileFor(Uri avatarUrl) async {
    try {
      final dir = await _directory();
      await dir.create(recursive: true);
      final name = base64Url.encode(utf8.encode(avatarUrl.toString()));
      return File(p.join(dir.path, name));
    } catch (e) {
      debugPrint('zuno/notifications: avatar cache unavailable ($e)');
      return null;
    }
  }

  Future<Uint8List?> read(Uri avatarUrl) async {
    final file = await _fileFor(avatarUrl);
    if (file == null) return null;
    try {
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<void> write(Uri avatarUrl, Uint8List bytes) async {
    final file = await _fileFor(avatarUrl);
    if (file == null) return;
    try {
      await file.writeAsBytes(bytes, flush: true);
    } catch (e) {
      debugPrint('zuno/notifications: could not cache avatar ($e)');
    }
  }
}
