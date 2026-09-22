import 'dart:math';

import '../security/secret_store.dart';

const _databaseKeyName = 'matrix_database_cipher';

class DatabaseKeyUnavailable implements Exception {
  final String message;
  DatabaseKeyUnavailable(this.message);

  @override
  String toString() => 'DatabaseKeyUnavailable: $message';
}

Future<String> obtainDatabaseCipher({
  SecretStore store = const SecureSecretStore(),
}) async {
  final existing = await _read(store);
  if (existing != null && existing.isNotEmpty) return existing;

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
