import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuno/core/matrix/database_key.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Map<String, String> installFakeStorage({
    bool failReads = false,
    bool failWrites = false,
    bool dropWrites = false,
  }) {
    final store = <String, String>{};
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = (call.arguments as Map).cast<String, Object?>();
      final key = args['key'] as String?;
      switch (call.method) {
        case 'read':
          if (failReads) throw PlatformException(code: 'locked');
          return store[key];
        case 'write':
          if (failWrites) throw PlatformException(code: 'keystore');
          if (!dropWrites) store[key!] = args['value'] as String;
          return null;
        case 'containsKey':
          return store.containsKey(key);
        default:
          return null;
      }
    });
    return store;
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('obtainDatabaseCipher', () {
    test('generates and persists a key on first run', () async {
      final store = installFakeStorage();
      final cipher = await obtainDatabaseCipher();

      expect(cipher, hasLength(databaseCipherLength));
      expect(store.values, contains(cipher));
    });

    test('returns the same key on every later run', () async {
      installFakeStorage();
      final first = await obtainDatabaseCipher();
      final second = await obtainDatabaseCipher();
      expect(second, first);
    });

    test('throws rather than returning a key that failed to store', () async {
      installFakeStorage(dropWrites: true);
      expect(obtainDatabaseCipher(), throwsA(isA<DatabaseKeyUnavailable>()));
    });

    test('throws when the keystore rejects the write outright', () async {
      installFakeStorage(failWrites: true);
      expect(obtainDatabaseCipher(), throwsA(isA<DatabaseKeyUnavailable>()));
    });
  });

  group('a database on disk', () {
    late String databasePath;
    const suffixes = ['', '-wal', '-shm', '-journal'];

    setUp(() {
      final directory = Directory.systemTemp.createTempSync('zuno_db_key');
      addTearDown(() => directory.deleteSync(recursive: true));
      databasePath = '${directory.path}/zuno.db';
      for (final suffix in suffixes) {
        File('$databasePath$suffix').writeAsStringSync('encrypted');
      }
    });

    List<bool> filesLeft() => [
      for (final suffix in suffixes) File('$databasePath$suffix').existsSync(),
    ];

    test('left without its key, as after a backup restored on a new phone, is '
        'deleted with its side files before a new key is made', () async {
      final store = installFakeStorage();

      final cipher = await obtainDatabaseCipher(databasePath: databasePath);

      expect(filesLeft(), [false, false, false, false]);
      expect(store.values, [cipher]);
    });

    test('whose key is still there is kept', () async {
      installFakeStorage();
      await obtainDatabaseCipher();

      await obtainDatabaseCipher(databasePath: databasePath);

      expect(filesLeft(), [true, true, true, true]);
    });

    test(
      'is kept when the key cannot be read, as while the phone is locked',
      () async {
        installFakeStorage(failReads: true);

        await expectLater(
          obtainDatabaseCipher(databasePath: databasePath),
          throwsA(isA<DatabaseKeyUnavailable>()),
        );
        expect(filesLeft(), [true, true, true, true]);
      },
    );
  });

  group('cipher generation', () {
    test('is 32 bytes of lowercase hex', () {
      final cipher = debugGenerateDatabaseCipher();
      expect(cipher, hasLength(databaseCipherLength));
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(cipher), isTrue);
    });

    test('contains nothing that could terminate a SQL string literal', () {
      for (var i = 0; i < 50; i++) {
        expect(debugGenerateDatabaseCipher(), isNot(contains("'")));
      }
    });

    test('does not repeat', () {
      final seen = {for (var i = 0; i < 50; i++) debugGenerateDatabaseCipher()};
      expect(seen, hasLength(50));
    });
  });
}
