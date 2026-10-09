import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import 'package:zuno/core/calls/matrixrtc/call_member_state.dart';
import 'package:zuno/core/matrix/client_lease.dart';
import 'package:zuno/core/matrix/database_key.dart';
import 'package:zuno/core/matrix/matrix_client_provider.dart';
import 'package:zuno/core/matrix/vodozemac_init.dart';
import 'package:zuno/core/matrix/zuno_client.dart';
import 'package:zuno/core/platform/platform_capabilities.dart';

import '../../helpers/fake_matrix.dart';
import '../../helpers/platform_capabilities.dart';

class _FakeVerification extends Fake implements KeyVerification {}

class _SyncTokenClient extends Client {
  _SyncTokenClient() : super('test', database: FakeDatabaseApi());

  String? token;

  @override
  String? get prevBatch => token;
}

void main() {
  group('the first sync', () {
    (_SyncTokenClient, ProviderContainer) start({String? token}) {
      final client = _SyncTokenClient()..token = token;
      final container = ProviderContainer(
        overrides: [matrixClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);
      container.listen(firstSyncProvider, (_, _) {});
      return (client, container);
    }

    Future<bool> settled(ProviderContainer container) async {
      var done = false;
      unawaited(
        container.read(firstSyncProvider.future).then((_) => done = true),
      );
      await pumpEventQueue();
      return done;
    }

    test('a session that synced before counts at once', () async {
      final (_, container) = start(token: 's1');

      expect(await settled(container), isTrue);
    });

    test('a fresh session waits for its first finished sync', () async {
      final (client, container) = start();

      expect(await settled(container), isFalse);

      client.onSyncStatus.add(SyncStatusUpdate(SyncStatus.finished));

      expect(await settled(container), isTrue);
    });

    test('a failed sync is not a first sync', () async {
      final (client, container) = start();

      client.onSyncStatus.add(SyncStatusUpdate(SyncStatus.error));

      expect(await settled(container), isFalse);
    });

    test('signing in again waits for that session\'s own first sync', () async {
      final (client, container) = start(token: 's1');
      await settled(container);

      client
        ..token = null
        ..accessToken = 'a1';
      client.onLoginStateChanged
        ..add(LoginState.loggedOut)
        ..add(LoginState.loggedIn);
      await pumpEventQueue();

      expect(await settled(container), isFalse);

      client.onSyncStatus.add(SyncStatusUpdate(SyncStatus.finished));

      expect(await settled(container), isTrue);
    });
  });

  Future<List<bool>> loginStatesAfter(List<LoginState> emitted) async {
    final client = buildTestClient()..accessToken = 'a0';
    final container = ProviderContainer(
      overrides: [matrixClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    final seen = <bool>[];
    container.listen(isLoggedInProvider, (_, next) {
      final loggedIn = next.value;
      if (loggedIn != null) seen.add(loggedIn);
    }, fireImmediately: true);
    await container.read(isLoggedInProvider.future);
    await pumpEventQueue();

    for (final state in emitted) {
      client.onLoginStateChanged.add(state);
      await pumpEventQueue();
    }
    return seen;
  }

  test('a token refresh never reads as signed out', () async {
    final seen = await loginStatesAfter([
      LoginState.softLoggedOut,
      LoginState.loggedIn,
    ]);

    expect(seen, isNot(contains(false)));
  });

  test('a refresh that fails without a verdict stays signed in', () async {
    final seen = await loginStatesAfter([LoginState.softLoggedOut]);

    expect(seen.last, isTrue);
  });

  test('a cleared session signs out', () async {
    final seen = await loginStatesAfter([
      LoginState.softLoggedOut,
      LoginState.loggedOut,
    ]);

    expect(seen.last, isFalse);
  });

  group('a sign-in in flight', () {
    test('holds while the call runs and lets go once it returns', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final call = Completer<void>();

      final signIn = container
          .read(signInInFlightProvider.notifier)
          .during(() => call.future);

      expect(container.read(signInInFlightProvider), isTrue);

      call.complete();
      await signIn;

      expect(container.read(signInInFlightProvider), isFalse);
    });

    test('lets go when the call fails', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(signInInFlightProvider.notifier)
            .during<void>(() async => throw Exception('refused')),
        throwsException,
      );

      expect(container.read(signInInFlightProvider), isFalse);
    });
  });

  for (final (label, provider) in [
    ('the client', matrixClientProvider),
    ('the upload client', uploadProgressHttpClientProvider),
  ]) {
    test('using $label before it is set up fails loudly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        () => container.read(provider),
        throwsA(
          isA<ProviderException>().having(
            (e) => e.exception,
            'exception',
            isA<UnimplementedError>(),
          ),
        ),
      );
    });
  }

  test('hands on each incoming verification request', () async {
    final client = buildTestClient();
    final container = ProviderContainer(
      overrides: [matrixClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    final request = _FakeVerification();

    final seen = <KeyVerification>[];
    container.listen(incomingKeyVerificationProvider, (_, next) {
      if (next.value case final verification?) seen.add(verification);
    });

    client.onKeyVerificationRequest.add(request);
    await pumpEventQueue();

    expect(seen, [same(request)]);
  });

  group('createMatrixClient', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    const secureStorage = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    const sqlcipher = MethodChannel('com.davidmartos96.sqflite_sqlcipher');
    const lease = MethodChannel('zuno/client_lease');

    late Directory support;
    late Map<String, String> secrets;
    late List<Map<Object?, Object?>> opened;
    late List<String> executed;
    late List<String> queried;
    late Map<String, int> pragmas;
    late List<List<Map<Object?, Object?>>> batches;
    late int busyOpens;
    late int keyedTables;
    late List<List<Object?>> cipherVersionRows;
    late int clientReads;
    late bool Function(int read) clientReadFails;
    late List<String> updates;
    late List<String> deletedDatabases;
    late List<MethodCall> leaseCalls;
    late List<int> openedWhenLeased;
    late String? Function(String kind) leaseAnswer;

    setUp(() async {
      support = Directory.systemTemp.createTempSync('zuno_support');
      secrets = {};
      opened = [];
      executed = [];
      queried = [];
      pragmas = {};
      batches = [];
      busyOpens = 0;
      keyedTables = 0;
      cipherVersionRows = [
        ['4.6.1 community'],
      ];
      clientReads = 0;
      clientReadFails = (_) => false;
      updates = [];
      deletedDatabases = [];
      leaseCalls = [];
      openedWhenLeased = [];
      var leases = 0;
      leaseAnswer = (kind) => '$kind-lease-${++leases}';
      forgetAppLeaseForTest();
      messenger.setMockMethodCallHandler(lease, (call) async {
        leaseCalls.add(call);
        if (call.method != 'acquire') return null;
        openedWhenLeased.add(opened.length + deletedDatabases.length);
        return leaseAnswer((call.arguments as Map)['kind'] as String);
      });
      messenger.setMockMethodCallHandler(
        pathProvider,
        (call) async => call.method == 'getApplicationSupportDirectory'
            ? support.path
            : null,
      );
      messenger.setMockMethodCallHandler(secureStorage, (call) async {
        final args = (call.arguments as Map).cast<String, Object?>();
        return switch (call.method) {
          'read' => secrets[args['key']],
          'write' => secrets[args['key'] as String] = args['value'] as String,
          'delete' => secrets.remove(args['key']),
          _ => null,
        };
      });
      messenger.setMockMethodCallHandler(sqlcipher, (call) async {
        final args = call.arguments is Map ? call.arguments as Map : const {};
        switch (call.method) {
          case 'openDatabase':
            opened.add(args);
            return opened.length <= busyOpens
                ? {'id': 1, 'recovered': true, 'recoveredInTransaction': true}
                : opened.length;
          case 'execute':
            executed.add('${args['sql']}');
            return null;
          case 'query':
            queried.add('${args['sql']}');
            if (pragmas['${args['sql']}'] case final value?) {
              return {
                'columns': ['value'],
                'rows': [
                  [value],
                ],
              };
            }
            if (args['sql'] == 'SELECT * FROM box_client' &&
                clientReadFails(++clientReads)) {
              throw PlatformException(
                code: 'sqlite_error',
                message: 'disk I/O error',
              );
            }
            if ('${args['sql']}'.contains('sqlite_master')) {
              return {
                'columns': ['count(*)'],
                'rows': [
                  [keyedTables],
                ],
              };
            }
            return '${args['sql']}'.contains('cipher_version')
                ? {
                    'columns': ['cipher_version'],
                    'rows': cipherVersionRows,
                  }
                : {'columns': <String>[], 'rows': <List<Object?>>[]};
          case 'batch':
            final operations = (args['operations'] as List)
                .cast<Map<Object?, Object?>>();
            batches.add(operations);
            return [
              for (final _ in operations) {'result': null},
            ];
          case 'update':
            updates.add('${args['sql']}');
            return 1;
          case 'insert':
            return 1;
          case 'deleteDatabase':
            deletedDatabases.add('${args['path']}');
            return null;
          default:
            return null;
        }
      });
      await ensureVodozemacInitialized(init: () async {});
      addTearDown(() {
        resetVodozemacInitForTest();
        for (final channel in [pathProvider, secureStorage, sqlcipher, lease]) {
          messenger.setMockMethodCallHandler(channel, null);
        }
        support.deleteSync(recursive: true);
      });
    });

    Future<void> noPause(Duration _) async {}

    Future<Client> create({bool backgroundSync = true}) async {
      final created = await createMatrixClient(
        backgroundSync: backgroundSync,
        pause: noPause,
      );
      addTearDown(created.client.dispose);
      expect(
        (created.client.httpClient as dynamic).inner,
        same(created.uploadProgressHttpClient),
      );
      return created.client;
    }

    Iterable<String> leaseMethods() => leaseCalls.map((c) => c.method);

    group('the client lease', () {
      test('the app takes its lease before it opens the database, waiting '
          'at most five seconds', () async {
        await create();

        expect(leaseCalls.single.arguments, {'kind': 'app', 'waitMs': 5000});
        expect(openedWhenLeased, [0]);
      });

      test('the app keeps its lease for good: a later start asks for nothing '
          'more, and letting a client go gives nothing back', () async {
        final first = await createMatrixClient(pause: noPause);
        await first.client.dispose();

        await create();

        expect(leaseMethods(), ['acquire']);
      });

      test(
        'starting over takes the app lease before it deletes anything',
        () async {
          final started = await startOverWithFreshStore();
          addTearDown(started.client.dispose);

          expect((leaseCalls.single.arguments as Map)['kind'], 'app');
          expect(openedWhenLeased, [0]);
        },
      );

      test('a background client takes a lease before it opens the database '
          'and gives it back once it is let go', () async {
        await obtainDatabaseCipher();
        final started = await createMatrixClient(backgroundSync: false);

        expect(leaseCalls.single.arguments, {
          'kind': 'background',
          'waitMs': 8000,
        });
        expect(openedWhenLeased, [0]);

        await started.client.dispose(closeDatabase: false);
        expect(leaseMethods(), ['acquire', 'release']);
        expect(leaseCalls.last.arguments, {'token': 'background-lease-1'});
      });

      test('a background client turned down opens nothing', () async {
        leaseAnswer = (_) => null;
        await obtainDatabaseCipher();

        await expectLater(
          createMatrixClient(backgroundSync: false),
          throwsA(isA<ClientLeaseDenied>()),
        );

        expect(opened, isEmpty);
        expect(leaseMethods(), ['acquire']);
      });

      test(
        'a background client that fails to start gives its lease back',
        () async {
          clientReadFails = (_) => true;
          await obtainDatabaseCipher();

          await expectLater(
            createMatrixClient(backgroundSync: false),
            throwsA(isA<Exception>()),
          );

          expect(leaseMethods(), ['acquire', 'release']);
        },
      );

      test('a background client that cannot even open the database gives '
          'its lease back', () async {
        File('${support.path}/zuno.db').writeAsStringSync('encrypted');

        await expectLater(
          createMatrixClient(backgroundSync: false),
          throwsA(isA<DatabaseKeyUnavailable>()),
        );

        expect(leaseMethods(), ['acquire', 'release']);
      });

      test('only the app\'s client may clear the store', () async {
        final app = await create();
        await obtainDatabaseCipher();
        final background = await create(backgroundSync: false);

        expect((app as ZunoClient).appClient, isTrue);
        expect((background as ZunoClient).appClient, isFalse);
      });
    });

    group('compaction', () {
      bool vacuums(String sql) => sql.toLowerCase().contains('vacuum');

      setUp(() => pragmas['PRAGMA auto_vacuum'] = 2);

      test('the app frees a bounded share of free pages at each open, '
          'reading each freed page back as a row', () async {
        await create();

        expect(queried, contains('PRAGMA incremental_vacuum(1000)'));
        expect(executed.where(vacuums), isEmpty);
      });

      test('a cache clear on the app database is given back only once the '
          'clear has committed', () async {
        ambientCapabilities = iosCapabilities;
        final client = await create();
        executed.clear();

        await client.database.clearCache();

        expect(executed, [
          'BEGIN IMMEDIATE',
          'COMMIT',
          'PRAGMA auto_vacuum = 2',
          'VACUUM',
        ]);
      });

      test('a background client never compacts at open', () async {
        await obtainDatabaseCipher();

        await create(backgroundSync: false);

        expect(queried.where(vacuums), isEmpty);
        expect(executed.where(vacuums), isEmpty);
      });
    });

    test('opens the database encrypted with the stored key', () async {
      await create();

      final open = opened.single;
      expect(open['path'], '${support.path}/zuno.db');
      expect(open['password'], hasLength(databaseCipherLength));
      expect(secrets.values, contains(open['password']));
    });

    test('starts while another isolate is inside a transaction on the shared '
        'database, without rolling that transaction back', () async {
      busyOpens = 1;
      await obtainDatabaseCipher();

      await create(backgroundSync: false);

      expect(opened, hasLength(2));
      expect(opened.last['password'], opened.first['password']);
      expect(executed, isNot(contains('ROLLBACK')));
    });

    test('opens it with the same key on the next start', () async {
      final previousRun = await createMatrixClient();
      await previousRun.client.dispose();

      await create();

      expect(opened, hasLength(2));
      expect(opened.last['password'], opened.first['password']);
    });

    bool controlsTransaction(String sql) =>
        sql == 'BEGIN IMMEDIATE' || sql == 'COMMIT' || sql == 'ROLLBACK';

    Future<void> writeInOneTransaction(Client client) =>
        client.database.transaction(() async {
          await client.database.storeAccountData('im.zuno.first', {'n': 1});
          await client.database.storeAccountData('im.zuno.second', {'n': 2});
        });

    test('on Android, a write transaction reaches the shared database as one '
        'native batch that begins and commits itself', () async {
      final client = await create();
      executed.clear();
      batches.clear();

      await writeInOneTransaction(client);

      expect(executed, isEmpty);
      final operations = batches.single;
      expect(operations.first, {
        'method': 'execute',
        'sql': 'BEGIN IMMEDIATE',
        'inTransaction': true,
      });
      expect(operations.last, {
        'method': 'execute',
        'sql': 'COMMIT',
        'inTransaction': false,
      });
      expect(
        operations.sublist(1, operations.length - 1).map((o) => o['method']),
        ['insert', 'insert'],
      );
    });

    test('on Android, opening the database sends no transaction control of '
        'its own outside a batch', () async {
      await create();

      expect(executed.where(controlsTransaction), isEmpty);
      expect(batches, isNotEmpty);
      for (final operations in batches) {
        expect(operations.first['sql'], 'BEGIN IMMEDIATE');
        expect(operations.last['sql'], 'COMMIT');
      }
    });

    test('on iOS, a write transaction keeps its own BEGIN and COMMIT calls '
        'around the batch', () async {
      ambientCapabilities = iosCapabilities;
      final client = await create();
      executed.clear();
      batches.clear();

      await writeInOneTransaction(client);

      expect(executed, ['BEGIN IMMEDIATE', 'COMMIT']);
      expect(batches.single.map((o) => o['method']), ['insert', 'insert']);
    });

    Iterable<String> wipes() =>
        updates.where((sql) => sql.startsWith('DELETE'));

    Future<void> failedLaunch() => expectLater(
      createMatrixClient(pause: noPause),
      throwsA(isA<Exception>()),
    );

    test('a headless client whose stored session cannot be read fails the push '
        'without wiping anything', () async {
      clientReadFails = (_) => true;
      await obtainDatabaseCipher();

      await expectLater(
        createMatrixClient(backgroundSync: false, pause: noPause),
        throwsA(isA<Exception>()),
      );

      expect(clientReads, 1);
      expect(wipes(), isEmpty);
      expect(deletedDatabases, isEmpty);
      expect(secrets, isNotEmpty);
    });

    test('a headless client never makes the database key, so it never '
        'deletes a database it cannot open', () async {
      File('${support.path}/zuno.db').writeAsStringSync('encrypted');

      await expectLater(
        createMatrixClient(backgroundSync: false, pause: noPause),
        throwsA(isA<DatabaseKeyUnavailable>()),
      );

      expect(secrets, isEmpty);
      expect(opened, isEmpty);
      expect(File('${support.path}/zuno.db').existsSync(), isTrue);
    });

    test('the app tries a failed start again with a fresh client', () async {
      clientReadFails = (read) => read == 1;

      final client = await create();

      expect(clientReads, 2);
      expect(client.onLoginStateChanged.value, LoginState.loggedOut);
      expect(wipes(), isEmpty);
    });

    test('an app start that keeps failing leaves the database and its key '
        'alone', () async {
      clientReadFails = (_) => true;

      await failedLaunch();

      expect(clientReads, greaterThan(1));
      expect(wipes(), isEmpty);
      expect(deletedDatabases, isEmpty);
      expect(secrets.values.single, opened.first['password']);
    });

    test(
      'no number of failed app starts deletes anything on its own',
      () async {
        clientReadFails = (_) => true;
        for (var launch = 0; launch < 5; launch++) {
          await failedLaunch();
        }

        expect(deletedDatabases, isEmpty);
        expect(wipes(), isEmpty);
        expect(secrets.values.single, opened.first['password']);
      },
    );

    test('starting over, when the user asks, signs out on a new database with '
        'a new key', () async {
      clientReadFails = (_) => deletedDatabases.isEmpty;
      await failedLaunch();
      final oldKey = secrets.values.single;

      final started = await startOverWithFreshStore();
      addTearDown(started.client.dispose);

      expect(deletedDatabases, ['${support.path}/zuno.db']);
      expect(secrets.values.single, isNot(oldKey));
      expect(opened.last['password'], secrets.values.single);
      expect(started.client.onLoginStateChanged.value, LoginState.loggedOut);
    });

    test('starting over keeps the database when its key cannot even be '
        'discarded', () async {
      clientReadFails = (_) => true;
      await failedLaunch();
      messenger.setMockMethodCallHandler(secureStorage, (call) async {
        final args = (call.arguments as Map).cast<String, Object?>();
        if (call.method == 'delete') {
          throw PlatformException(code: 'keystore', message: 'unusable');
        }
        return call.method == 'read' ? secrets[args['key']] : null;
      });

      await expectLater(
        startOverWithFreshStore(),
        throwsA(isA<DatabaseKeyUnavailable>()),
      );

      expect(deletedDatabases, isEmpty);
      expect(secrets, isNotEmpty);
    });

    group('the derived database key', () {
      final salt = List<int>.generate(16, (i) => i + 1);
      final saltHex = salt
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final rawKey = "x'${'ab' * 32}'";

      setUp(() async {
        File('${support.path}/zuno.db')
            .writeAsBytesSync([...salt, ...List.filled(64, 7)]);
        keyedTables = 3;
        await obtainDatabaseCipher();
      });

      Future<void> until(bool Function() done) async {
        for (var i = 0; i < 600 && !done(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      test('a cold start opens with the cached key when it fits the '
          'file', () async {
        secrets['matrix_database_raw_key'] = '$saltHex:$rawKey';

        await create();

        expect(opened.map((o) => o['password']), everyElement(rawKey));
      });

      test('an app start that needed the passphrase caches the key for the '
          'next cold start', () async {
        final passphrase = secrets['matrix_database_cipher'];

        await create();
        await until(() => secrets.containsKey('matrix_database_raw_key'));

        expect(opened.first['password'], passphrase);
        expect(
          secrets['matrix_database_raw_key'],
          matches(RegExp("^$saltHex:x'[0-9a-f]{64}'\$")),
        );
      });

      test('a background client never derives the key', () async {
        final started = await createMatrixClient(
          backgroundSync: false,
          pause: noPause,
        );
        addTearDown(started.client.dispose);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(secrets.containsKey('matrix_database_raw_key'), isFalse);
      });
    });

    test('starts signed out when nothing is stored', () async {
      final client = await create();

      expect(client.isLogged(), isFalse);
      expect(client.onLoginStateChanged.value, LoginState.loggedOut);
    });

    test('is set up for Zuno', () async {
      final client = await create();

      expect(client.clientName, 'Zuno');
      expect(client.importantStateEvents, contains(callMemberEventType));
      expect(
        client.roomPreviewLastEvents,
        containsAll({
          EventTypes.Message,
          EventTypes.Encrypted,
          EventTypes.Sticker,
        }),
      );
      expect(client.verificationMethods, {
        KeyVerificationMethod.emoji,
        KeyVerificationMethod.qrShow,
        KeyVerificationMethod.qrScan,
      });
      expect(client.syncErrorTimeoutSec, 1);
    });

    test('the app client does crypto off the UI thread', () async {
      final client = await create();

      expect(client.nativeImplementations, isA<NativeImplementationsIsolate>());
    });

    test('a headless client does crypto in place', () async {
      await obtainDatabaseCipher();
      final client = await create(backgroundSync: false);

      expect(
        client.nativeImplementations,
        isNot(isA<NativeImplementationsIsolate>()),
      );
    });

    for (final (label, rows) in [
      ('no cipher version', <List<Object?>>[]),
      (
        'an empty cipher version',
        [
          <Object?>[null],
        ],
      ),
    ]) {
      test('refuses a database with $label, never writing plaintext', () async {
        cipherVersionRows = rows;

        await expectLater(
          createMatrixClient(pause: noPause),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('SQLCipher is not available'),
            ),
          ),
        );
      });
    }
  });
}
