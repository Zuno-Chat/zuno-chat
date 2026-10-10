import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:sqflite_sqlcipher/sqflite.dart' as sqflite;
import 'package:vodozemac/vodozemac.dart' as vod;

import '../errors/best_effort.dart';
import '../errors/caught_errors.dart';
import '../security/secret_store.dart';
import 'shared_database_open.dart';
import 'vodozemac_init.dart';

const _rawKeyName = 'matrix_database_raw_key';
const _sqlCipherSaltLength = 16;
const _sqlCipherKeyLength = 32;
const _sqlCipherKdfIterations = 256000;

final _cachedEntry = RegExp(r"^([0-9a-f]{32}):(x'[0-9a-f]{64}')$");

typedef DeriveRawKey = Future<String> Function(
  String passphrase,
  List<int> salt,
);

typedef _CachedKey = ({String salt, String rawKey});

Future<void> _pause(Duration delay) => Future<void>.delayed(delay);

Uint8List pbkdf2HmacSha512(
  List<int> password,
  List<int> salt, {
  required int iterations,
  required int length,
}) {
  final hmac = Hmac(sha512, password);
  var block = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final result = Uint8List.fromList(block);
  for (var round = 1; round < iterations; round++) {
    block = hmac.convert(block).bytes;
    for (var i = 0; i < result.length; i++) {
      result[i] ^= block[i];
    }
  }
  return result.sublist(0, length);
}

Future<String> deriveDatabaseRawKey(String passphrase, List<int> salt) {
  final password = utf8.encode(passphrase);
  final fileSalt = Uint8List.fromList(salt);
  return Isolate.run(
    () => _rawKeyLiteral(
      pbkdf2HmacSha512(
        password,
        fileSalt,
        iterations: _sqlCipherKdfIterations,
        length: _sqlCipherKeyLength,
      ),
    ),
  );
}

Future<String> deriveDatabaseRawKeyNatively(String passphrase, List<int> salt) {
  final password = utf8.encode(passphrase);
  final fileSalt = Uint8List.fromList(salt);
  return Isolate.run(() async {
    await ensureVodozemacInitialized();
    final key = vod.CryptoUtils.pbkdf2(
      passphrase: password,
      salt: fileSalt,
      iterations: _sqlCipherKdfIterations,
    );
    if (key.length != _sqlCipherKeyLength) {
      throw StateError('pbkdf2 gave ${key.length} bytes');
    }
    return _rawKeyLiteral(key);
  });
}

Future<String> deriveDatabaseRawKeyFast(String passphrase, List<int> salt) =>
    deriveDatabaseRawKeyNatively(passphrase, salt).catchError((
      Object error,
      StackTrace stack,
    ) {
      reportCaught('derive the database key natively', error, stack);
      return deriveDatabaseRawKey(passphrase, salt);
    });

Future<sqflite.Database> openSharedDatabaseWithCachedKey(
  String path, {
  required String passphrase,
  SecretStore store = const SecureSecretStore(),
  Future<void> Function(Duration delay) wait = _pause,
}) async {
  final rawKey = await _rawKeyFor(path, store);
  if (rawKey != null) {
    final database = await _openWithRawKey(path, rawKey, wait);
    if (database != null) return database;
    await _forgetQuietly(store);
  }
  return openSharedDatabase(path, password: passphrase, wait: wait);
}

Future<bool> cacheDatabaseRawKey(
  String path, {
  required String passphrase,
  SecretStore store = const SecureSecretStore(),
  DeriveRawKey derive = deriveDatabaseRawKey,
}) async {
  try {
    final salt = await _fileSalt(path);
    if (salt == null) return false;
    final cached = _parse(await store.read(_rawKeyName));
    if (cached?.salt == _hex(salt)) return true;
    final rawKey = await derive(passphrase, salt);
    if (!listEquals(await _fileSalt(path), salt)) return false;
    if (!await _opensKeyedTables(path, rawKey)) return false;
    await store.write(_rawKeyName, '${_hex(salt)}:$rawKey');
    return true;
  } catch (error, stack) {
    reportCaught('cache the derived database key', error, stack);
    return false;
  }
}

Future<void> forgetDatabaseRawKey(SecretStore store) =>
    store.delete(_rawKeyName);

Future<String?> _rawKeyFor(String path, SecretStore store) async {
  final String? entry;
  try {
    entry = await store.read(_rawKeyName);
  } catch (error, stack) {
    reportCaught('read the cached database key', error, stack);
    return null;
  }
  if (entry == null) return null;
  final cached = _parse(entry);
  final salt = await _fileSalt(path);
  if (cached != null && salt != null && cached.salt == _hex(salt)) {
    return cached.rawKey;
  }
  await _forgetQuietly(store);
  return null;
}

Future<sqflite.Database?> _openWithRawKey(
  String path,
  String rawKey,
  Future<void> Function(Duration delay) wait,
) async {
  if (!await _opensKeyedTables(path, rawKey)) return null;
  try {
    return await openSharedDatabase(path, password: rawKey, wait: wait);
  } catch (error, stack) {
    reportCaught('open the database with the cached key', error, stack);
    return null;
  }
}

Future<bool> _opensKeyedTables(String path, String rawKey) async {
  final sqflite.Database probe;
  try {
    probe = await sqflite.openDatabase(
      path,
      password: rawKey,
      readOnly: true,
      singleInstance: false,
    );
  } catch (error, stack) {
    reportCaught('open the database with the derived key', error, stack);
    return false;
  }
  try {
    return await readsKeyedTables(probe);
  } catch (error, stack) {
    reportCaught('read the database with the derived key', error, stack);
    return false;
  } finally {
    await runBestEffort(probe.close, label: 'close the database key probe');
  }
}

Future<void> _forgetQuietly(SecretStore store) => runBestEffort(
  () => forgetDatabaseRawKey(store),
  label: 'forget the cached database key',
);

_CachedKey? _parse(String? entry) {
  final match = entry == null ? null : _cachedEntry.firstMatch(entry);
  if (match == null) return null;
  return (salt: match.group(1)!, rawKey: match.group(2)!);
}

Future<Uint8List?> _fileSalt(String path) async {
  final List<int> header;
  try {
    header = await File(path)
        .openRead(0, _sqlCipherSaltLength)
        .expand((chunk) => chunk)
        .toList();
  } on PathNotFoundException {
    return null;
  } on FileSystemException catch (error, stack) {
    reportCaught('read the database salt', error, stack);
    return null;
  }
  return header.length == _sqlCipherSaltLength
      ? Uint8List.fromList(header)
      : null;
}

String _rawKeyLiteral(List<int> key) => "x'${_hex(key)}'";

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
