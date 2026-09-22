import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureSecretStore implements SecretStore {
  final FlutterSecureStorage _storage;

  const SecureSecretStore([
    this._storage = const FlutterSecureStorage(aOptions: AndroidOptions()),
  ]);

  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
