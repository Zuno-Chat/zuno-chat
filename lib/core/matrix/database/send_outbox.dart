import 'dart:convert';
import 'dart:io' show PathNotFoundException;
import 'dart:typed_data';

import 'package:file/file.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;

import '../../errors/best_effort.dart';
import '../../errors/caught_errors.dart';
import '../../files/file_system.dart';
import '../../files/unique_name.dart';

const _scheme = 'cache';
const _fileKind = 'file';
const _kinds = [_fileKind, 'thumbnail'];
const _dirName = 'send_outbox';

Future<Directory> Function() _parent = applicationSupportDirectory;
Directory? _located;

@visibleForTesting
set sendOutboxParent(Future<Directory> Function() value) {
  _parent = value;
  _located = null;
}

Future<Directory> _directory() async =>
    _located ??= (await _parent()).childDirectory(_dirName);

String _name(String kind, String id) =>
    '$kind-${base64Url.encode(utf8.encode(id))}';

String _nameOf(Uri uri) => _name(uri.host, uri.pathSegments.join('/'));

String? _idOf(String name) {
  final dash = name.indexOf('-');
  if (dash < 0) return null;
  try {
    return utf8.decode(base64Url.decode(name.substring(dash + 1)));
  } on FormatException {
    return null;
  }
}

Future<Uint8List?> _read(String name) async {
  try {
    return await (await _directory()).childFile(name).readAsBytes();
  } on PathNotFoundException {
    return null;
  } catch (e, s) {
    reportCaught('read a file kept until it is sent', e, s);
    return null;
  }
}

Future<void> _write(String name, Uint8List bytes) async {
  final directory = await _directory();
  await directory.create(recursive: true);
  final part = directory.childFile('$name.${uniqueName()}.part');
  try {
    await part.writeAsBytes(bytes, flush: true);
    await part.rename(directory.childFile(name).path);
  } catch (_) {
    await _deleteEntity(part);
    rethrow;
  }
}

Future<bool> _delete(String name) async =>
    _deleteEntity((await _directory()).childFile(name));

Future<bool> _deleteEntity(FileSystemEntity entity) async {
  try {
    await entity.delete(recursive: entity is Directory);
    return true;
  } on PathNotFoundException {
    return false;
  } catch (e, s) {
    reportCaught('delete a file kept until it was sent', e, s);
    return false;
  }
}

Future<Uint8List?> unsentFileBytes(Event event) async {
  final txid = event.transactionId;
  return txid == null ? null : _read(_name(_fileKind, txid));
}

Future<bool> hasUnsentFile(Event event) async {
  final txid = event.transactionId;
  if (txid == null) return false;
  return (await _directory()).childFile(_name(_fileKind, txid)).exists();
}

Future<void> dropSendOutboxOrphans(Client client) async {
  final database = client.database;
  if (database is SendOutbox) await database._dropOrphans(client.rooms);
}

mixin SendOutbox on DatabaseApi {
  final _writtenThisRun = <String>{};

  @override
  Future<void> storeFile(Uri mxcUri, Uint8List bytes, int time) async {
    if (mxcUri.scheme != _scheme) return super.storeFile(mxcUri, bytes, time);
    final name = _nameOf(mxcUri);
    _writtenThisRun.add(name);
    await runBestEffort(
      () => _write(name, bytes),
      label: 'keep a file until it is sent',
    );
  }

  @override
  Future<Uint8List?> getFile(Uri mxcUri) =>
      mxcUri.scheme == _scheme ? _read(_nameOf(mxcUri)) : super.getFile(mxcUri);

  @override
  Future<bool> deleteFile(Uri mxcUri) => mxcUri.scheme == _scheme
      ? _delete(_nameOf(mxcUri))
      : super.deleteFile(mxcUri);

  @override
  Future<void> removeEvent(String eventId, String roomId) async {
    await super.removeEvent(eventId, roomId);
    for (final kind in _kinds) {
      await _delete(_name(kind, eventId));
    }
  }

  @override
  Future<void> clearCache() async {
    await _deleteAll();
    await super.clearCache();
  }

  @override
  Future<void> clear() async {
    await _deleteAll();
    await super.clear();
  }

  Future<void> _deleteAll() async {
    _writtenThisRun.clear();
    await runBestEffort(
      () async => _deleteEntity(await _directory()),
      label: 'delete the files kept until they are sent',
    );
  }

  Future<void> _dropOrphans(List<Room> rooms) async {
    final List<FileSystemEntity> stored;
    try {
      stored = await (await _directory()).list().toList();
    } on PathNotFoundException {
      return;
    }
    final waiting = <String, bool>{};
    for (final entity in stored) {
      final name = p.basename(entity.path).split('.').first;
      if (_writtenThisRun.contains(name)) continue;
      final txid = _idOf(name);
      final keep =
          txid != null && (waiting[txid] ??= await _waitsToBeSent(txid, rooms));
      if (!keep) await _deleteEntity(entity);
    }
  }

  Future<bool> _waitsToBeSent(String txid, List<Room> rooms) async {
    for (final room in rooms) {
      final event = await getEventById(txid, room);
      if (event != null && !event.status.isSent) return true;
    }
    return false;
  }
}
