import 'package:zuno/core/security/secret_store.dart';

class InMemorySecretStore implements SecretStore {
  final Map<String, String> values = {};
  bool failReads = false;
  bool failWrites = false;
  bool failDeletes = false;
  Future<void> Function()? beforeRead;
  int reads = 0;
  int writes = 0;

  @override
  Future<String?> read(String key) async {
    reads++;
    final value = values[key];
    await beforeRead?.call();
    if (failReads) throw StateError('keystore unavailable');
    return value;
  }

  @override
  Future<void> write(String key, String value) async {
    writes++;
    if (failWrites) throw StateError('keystore unavailable');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (failDeletes) throw StateError('keystore unavailable');
    values.remove(key);
  }
}
