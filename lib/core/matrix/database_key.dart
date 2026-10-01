import 'dart:io';
import 'dart:math';

import '../errors/best_effort.dart';
import '../security/secret_store.dart';
import 'database_raw_key.dart';

const _databaseKeyName = 'matrix_database_cipher';

class DatabaseKeyUnavailable implements Exception {
  final String message;
  DatabaseKeyUnavailable(this.message);

  @override
  String toString() => 'DatabaseKeyUnavailable: $message';
}

Future<String> obtainDatabaseCipher({
  SecretStore store = const SecureSecretStore(),
  String? databasePath,
  bool createIfMissing = true,
}) async {
  final existing = await _read(store);
  if (existing != null && existing.isNotEmpty) return existing;
  if (!createIfMissing) {
    throw DatabaseKeyUnavailable(
      'there is no database key yet, and only the app may make one',
    );
  }

  if (databasePath != null) await _deleteDatabaseFiles(databasePath);
  await runBestEffort(
    () => forgetDatabaseRawKey(store),
    label: 'forget the derived key of the replaced database',
  );
  final generated = _generateCipher();
  try {
    await store.write(_databaseKeyName, generated);
  } catch (e) {
    throw DatabaseKeyUnavailable('could not write the database key: $e');
  }

  final readBack = await _read(store);
  if (readBack != generated) {
    throw DatabaseKeyUnavailable(
      'the database key did not survive a write/read round trip — '
      'refusing to encrypt with a key that cannot be recovered',
    );
  }
  return generated;
}

Future<void> discardDatabaseCipher({
  SecretStore store = const SecureSecretStore.discardingUnreadable(),
}) async {
  try {
    await forgetDatabaseRawKey(store);
    await store.delete(_databaseKeyName);
  } catch (e) {
    throw DatabaseKeyUnavailable('could not discard the database key: $e');
  }
}

Future<void> _deleteDatabaseFiles(String path) async {
  try {
    for (final suffix in const ['', '-wal', '-shm', '-journal']) {
      final file = File('$path$suffix');
      if (await file.exists()) await file.delete();
    }
  } catch (e) {
    throw DatabaseKeyUnavailable(
      'could not delete the database its lost key encrypted: $e',
    );
  }
}

Future<String?> _read(SecretStore store) async {
  try {
    return await store.read(_databaseKeyName);
  } catch (e) {
    throw DatabaseKeyUnavailable('could not read the database key: $e');
  }
}

String _generateCipher() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

String debugGenerateDatabaseCipher() => _generateCipher();

const databaseCipherLength = 64;
