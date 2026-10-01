import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqflite;

import 'package:zuno/core/matrix/database_key.dart';
import 'package:zuno/core/matrix/database_raw_key.dart';

import '../../helpers/in_memory_secret_store.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<int> _bytes(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PBKDF2-HMAC-SHA512', () {
    for (final (label, password, salt, iterations, length, expected) in [
      (
        'one iteration',
        'password',
        'salt',
        1,
        64,
        '867f70cf1ade02cff3752599a3a53dc4af34c7a669815ae5d513554e1c8cf252'
            'c02d470a285a0501bad999bfe943c08f050235d7d68b1da55e63f73b60a57fce',
      ),
      (
        'two iterations',
        'password',
        'salt',
        2,
        64,
        'e1d9c16aa681708a45f5c7c4e215ceb66e011a2e9f0040713f18aefdb866d53c'
            'f76cab2868a39b9f7840edce4fef5a82be67335c77a6068e04112754f27ccf4e',
      ),
      (
        '4096 iterations',
        'password',
        'salt',
        4096,
        64,
        'd197b1b33db0143e018b12f3d1d1479e6cdebdcc97c5c0f87f6902e072f457b5'
            '143f30602641b3d55cd335988cb36b84376060ecd532e039b742a239434af2d5',
      ),
      (
        'a long password and salt',
        'passwordPASSWORDpassword',
        'saltSALTsaltSALTsaltSALTsaltSALTsalt',
        4096,
        64,
        '8c0511f4c6e597c6ac6315d8f0362e225f3c501495ba23b868c005174dc4ee71'
            '115b59f9e60cd9532fa33e0f75aefe30225c583a186cd82bd4daea9724a3d3b8',
      ),
      (
        'a password and salt holding NUL bytes',
        'pass\u0000word',
        'sa\u0000lt',
        4096,
        64,
        '9d9e9c4cd21fe4be24d5b8244c759665f39d98fc12a9ca759bb021db3cfadf34'
            '5844aebe70dd8b2f6966f25f3613e1187bbd24ed2ca43ed13b246e4675be7ab9',
      ),
      (
        'a 32-byte key',
        'password',
        'salt',
        1,
        32,
        '867f70cf1ade02cff3752599a3a53dc4af34c7a669815ae5d513554e1c8cf252',
      ),
    ]) {
      test('matches the published vector for $label', () {
        final key = pbkdf2HmacSha512(
          utf8.encode(password),
          utf8.encode(salt),
          iterations: iterations,
          length: length,
        );

        expect(_hex(key), expected);
      });
    }

    test('derives the raw key SQLCipher 4.10 itself derives for a database '
        'made with the passphrase', () async {
      final rawKey = await deriveDatabaseRawKey(
        '0123456789abcdef' * 4,
        _bytes('be7d9aac3649c57585d5872a6ea11779'),
      );

      expect(
        rawKey,
        "x'a61862bee9ad90b36940f5feefdb799d449226a430439bb70ee3dcdc10f30dcd'",
      );
    });
  });

  group('the derived key cache', () {
    const channel = MethodChannel('com.davidmartos96.sqflite_sqlcipher');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const passphrase =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    final rawKey = "x'${'ab' * 32}'";
    final salt = List<int>.generate(16, (i) => i + 1);

    late String path;
    late List<int> fileBytes;
    late InMemorySecretStore store;
    late Set<String> openingKeys;
    late bool Function(Map<Object?, Object?> args) refuseOpen;
    late int keyedTables;
    late List<Map<Object?, Object?>> opens;
    late List<String> events;
    late List<(String, String)> derived;

    Future<void> noWait(Duration _) async {}

    Future<String> deriveFake(String passphrase, List<int> salt) async {
      derived.add((passphrase, _hex(salt)));
      return rawKey;
    }

    bool isProbe(Map<Object?, Object?> args) =>
        args['singleInstance'] == false && args['readOnly'] == true;

    setUp(() {
      final directory = Directory.systemTemp.createTempSync('zuno_raw_key');
      addTearDown(() => directory.deleteSync(recursive: true));
      path = '${directory.path}/zuno.db';
      fileBytes = [...salt, for (var i = 0; i < 4080; i++) (i * 7) & 0xff];
      File(path).writeAsBytesSync(fileBytes);
      store = InMemorySecretStore();
      openingKeys = {passphrase, rawKey};
      refuseOpen = (_) => false;
      keyedTables = 12;
      opens = [];
      events = [];
      derived = [];
      var nextId = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        final args = call.arguments is Map ? call.arguments as Map : const {};
        switch (call.method) {
          case 'openDatabase':
            opens.add(args);
            final kind = isProbe(args) ? 'probe' : 'shared';
            if (!openingKeys.contains(args['password']) || refuseOpen(args)) {
              events.add('$kind refused');
              throw PlatformException(
                code: 'sqlite_error',
                message: 'open_failed $path',
              );
            }
            final id = ++nextId;
            events.add('$kind $id opened');
            return {'id': id};
          case 'query':
            events.add('query ${args['id']}');
            return {
              'columns': ['tables'],
              'rows': [
                [keyedTables],
              ],
            };
          case 'closeDatabase':
            events.add('close ${args['id']}');
            return null;
          case 'deleteDatabase':
            events.add('delete ${args['path']}');
            return null;
          default:
            return null;
        }
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    });

    Future<bool> cacheKey() => cacheDatabaseRawKey(
      path,
      passphrase: passphrase,
      store: store,
      derive: deriveFake,
    );

    Future<sqflite.Database> open() async {
      final database = await openSharedDatabaseWithCachedKey(
        path,
        passphrase: passphrase,
        store: store,
        wait: noWait,
      );
      addTearDown(database.close);
      return database;
    }

    Future<void> cacheThenRestart() async {
      expect(await cacheKey(), isTrue);
      opens.clear();
      events.clear();
    }

    List<Object?> sharedPasswords() => [
      for (final args in opens)
        if (!isProbe(args)) args['password'],
    ];

    group('opening the database', () {
      test('opens with the cached key once a private read-only connection '
          'has read the keyed tables with it', () async {
        await cacheThenRestart();

        await open();

        expect(opens.first['password'], rawKey);
        expect(isProbe(opens.first), isTrue);
        expect(sharedPasswords(), [rawKey]);
        expect(events, [
          'probe 2 opened',
          'query 2',
          'close 2',
          'shared 3 opened',
        ]);
      });

      test('opens with the passphrase alone when no key is cached', () async {
        await open();

        expect(opens, hasLength(1));
        expect(opens.single['password'], passphrase);
        expect(isProbe(opens.single), isFalse);
      });

      test('forgets a key cached for another database file before opening '
          'anything with it', () async {
        await cacheThenRestart();
        File(path).writeAsBytesSync([
          ...List<int>.filled(16, 0x5a),
          ...fileBytes.skip(16),
        ]);

        await open();

        expect(opens.map((args) => args['password']), [passphrase]);
        expect(store.values, isEmpty);
      });

      test('falls back to the passphrase when the cached key does not open '
          'the file, forgets it, and deletes nothing on disk', () async {
        await cacheThenRestart();
        openingKeys.remove(rawKey);

        await open();

        expect(events.first, 'probe refused');
        expect(sharedPasswords(), [passphrase]);
        expect(store.values, isEmpty);
        expect(events.where((event) => event.startsWith('delete')), isEmpty);
        expect(File(path).readAsBytesSync(), fileBytes);
      });

      test('never uses a cached key for the shared connection when its '
          'private connection reads none of the keyed tables', () async {
        await cacheThenRestart();
        keyedTables = 0;

        await open();

        expect(events.take(3), ['probe 2 opened', 'query 2', 'close 2']);
        expect(sharedPasswords(), [passphrase]);
        expect(store.values, isEmpty);
      });

      test('falls back to the passphrase when the shared open with the '
          'proven key still fails', () async {
        await cacheThenRestart();
        refuseOpen = (args) => !isProbe(args) && args['password'] == rawKey;

        await open();

        expect(sharedPasswords(), [rawKey, passphrase]);
        expect(store.values, isEmpty);
      });

      test(
        'forgets a damaged cache entry and opens with the passphrase',
        () async {
          await cacheThenRestart();
          store.values.updateAll((_, _) => 'not a key');

          await open();

          expect(opens.map((args) => args['password']), [passphrase]);
          expect(store.values, isEmpty);
        },
      );

      test('keeps a cached key it cannot read, and opens with the '
          'passphrase', () async {
        await cacheThenRestart();
        final entry = Map.of(store.values);
        store.failReads = true;

        await open();

        expect(opens.map((args) => args['password']), [passphrase]);
        expect(store.values, entry);
      });

      test(
        'never tries the cached key on a database file that is gone',
        () async {
          await cacheThenRestart();
          File(path).deleteSync();

          await open();

          expect(opens.map((args) => args['password']), [passphrase]);
          expect(store.values, isEmpty);
        },
      );
    });

    group('caching the derived key', () {
      test('derives the key from the passphrase and the salt the file '
          'starts with, proves it on a private read-only connection, and '
          'caches it', () async {
        expect(await cacheKey(), isTrue);

        expect(derived, [(passphrase, '0102030405060708090a0b0c0d0e0f10')]);
        expect(opens.single['password'], rawKey);
        expect(isProbe(opens.single), isTrue);
        expect(events, ['probe 1 opened', 'query 1', 'close 1']);
        expect(store.values, isNotEmpty);
      });

      test('derives nothing again while the cached key matches the '
          'file', () async {
        await cacheKey();

        expect(await cacheKey(), isTrue);

        expect(derived, hasLength(1));
      });

      test('derives again for a database file that replaced the cached '
          'one', () async {
        await cacheKey();
        final newSalt = List<int>.filled(16, 0x5a);
        File(path).writeAsBytesSync([...newSalt, ...fileBytes.skip(16)]);

        expect(await cacheKey(), isTrue);

        expect(derived.map((entry) => entry.$2), [
          '0102030405060708090a0b0c0d0e0f10',
          '5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a',
        ]);
      });

      test('never caches a derived key that does not open the file', () async {
        openingKeys.remove(rawKey);

        expect(await cacheKey(), isFalse);

        expect(store.values, isEmpty);
      });

      test('never caches a derived key whose private connection reads none '
          'of the keyed tables', () async {
        keyedTables = 0;

        expect(await cacheKey(), isFalse);

        expect(events, ['probe 1 opened', 'query 1', 'close 1']);
        expect(store.values, isEmpty);
      });

      test('caches nothing for a database file replaced while the key was '
          'being derived', () async {
        final deriving = cacheDatabaseRawKey(
          path,
          passphrase: passphrase,
          store: store,
          derive: (passphrase, salt) async {
            File(path).writeAsBytesSync([
              ...List<int>.filled(16, 0x5a),
              ...fileBytes.skip(16),
            ]);
            return rawKey;
          },
        );

        expect(await deriving, isFalse);

        expect(opens, isEmpty);
        expect(store.values, isEmpty);
      });

      test('derives nothing when there is no database file', () async {
        File(path).deleteSync();

        expect(await cacheKey(), isFalse);

        expect(derived, isEmpty);
      });

      test('reports a derivation that fails as nothing cached, without '
          'throwing', () async {
        final cached = await cacheDatabaseRawKey(
          path,
          passphrase: passphrase,
          store: store,
          derive: (_, _) async => throw StateError('no memory'),
        );

        expect(cached, isFalse);
        expect(store.values, isEmpty);
      });

      test('reports a key the store refuses as nothing cached, without '
          'throwing', () async {
        store.failWrites = true;

        expect(await cacheKey(), isFalse);
      });
    });

    group('the database key', () {
      test('discarding it forgets the key derived from it', () async {
        await obtainDatabaseCipher(store: store);
        await cacheKey();
        expect(store.values, hasLength(2));

        await discardDatabaseCipher(store: store);

        expect(store.values, isEmpty);
      });

      test('a new one forgets the key derived for the database it '
          'replaces', () async {
        await cacheKey();
        expect(store.values, hasLength(1));

        final fresh = await obtainDatabaseCipher(store: store);

        expect(store.values.values, [fresh]);
      });

      test('an existing one keeps the key derived from it', () async {
        final key = await obtainDatabaseCipher(store: store);
        await cacheKey();

        expect(await obtainDatabaseCipher(store: store), key);

        expect(store.values, hasLength(2));
      });
    });
  });
}
