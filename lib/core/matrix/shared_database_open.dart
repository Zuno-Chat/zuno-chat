import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, listEquals;
import 'package:sqflite_sqlcipher/sqflite.dart' as sqflite;

const sharedDatabaseWaitBudget = Duration(seconds: 1);

const _firstRetryDelay = Duration(milliseconds: 10);
const _maxRetryDelay = Duration(milliseconds: 250);

final _plaintextHeader = ascii.encode('SQLite format 3\u0000');

const _keyedTablesProbe =
    "SELECT count(*) FROM sqlite_master WHERE type = 'table' "
    "AND substr(name, 1, 7) <> 'sqlite_' AND name <> 'android_metadata'";

enum _Header { encrypted, plaintext, unreadable }

Future<void> _pause(Duration delay) => Future<void>.delayed(delay);

Future<sqflite.Database> openSharedDatabase(
  String path, {
  required String password,
  Future<void> Function(Duration delay) wait = _pause,
}) async {
  var delay = _firstRetryDelay;
  var waited = Duration.zero;
  while (true) {
    final database = await _openWithKey(path, password);
    if (database != null) return database;
    if (waited >= sharedDatabaseWaitBudget) {
      return _recoverAbandonedTransaction(path);
    }
    if (waited == Duration.zero) {
      debugPrint('zuno/db: another isolate is inside a transaction, waiting');
    }
    await wait(delay);
    waited += delay;
    delay = delay * 2 < _maxRetryDelay ? delay * 2 : _maxRetryDelay;
  }
}

Future<sqflite.Database?> _openWithKey(String path, String password) async {
  try {
    return await sqflite.openDatabase(path, password: password);
  } on TypeError {
    return null;
  }
}

Future<sqflite.Database> _recoverAbandonedTransaction(String path) async {
  if (await _readHeader(path) != _Header.encrypted) {
    throw StateError(
      'A transaction on the database was never finished, and there is no '
      'encrypted database on disk to reopen without the key.',
    );
  }
  debugPrint('zuno/db: rolling back a transaction no isolate finished');
  final database = await sqflite.databaseFactory.openDatabase(
    path,
    options: sqflite.OpenDatabaseOptions(rollbackActiveTransactionOnOpen: true),
  );
  final header = await _readHeader(path);
  if (header == _Header.plaintext) {
    await sqflite.databaseFactory.deleteDatabase(path);
    throw StateError(
      'Reopening the database without the key left it unencrypted, so it was '
      'removed.',
    );
  }
  if (!await readsKeyedTables(database)) {
    await database.close();
    throw StateError(
      'The database reopened without the key is not the keyed connection, so '
      'it was closed.',
    );
  }
  if (header == _Header.unreadable) {
    throw StateError(
      'The database could not be read back after reopening it without the '
      'key, so it was left as it is.',
    );
  }
  return database;
}

Future<bool> readsKeyedTables(sqflite.Database database) async {
  try {
    final tables = sqflite.Sqflite.firstIntValue(
      await database.rawQuery(_keyedTablesProbe),
    );
    return (tables ?? 0) > 0;
  } on sqflite.DatabaseException {
    return false;
  }
}

Future<_Header> _readHeader(String path) async {
  final List<int> header;
  try {
    header = await File(path)
        .openRead(0, _plaintextHeader.length)
        .expand((chunk) => chunk)
        .toList();
  } on FileSystemException {
    return _Header.unreadable;
  }
  if (header.length < _plaintextHeader.length) return _Header.unreadable;
  return listEquals(header, _plaintextHeader)
      ? _Header.plaintext
      : _Header.encrypted;
}
