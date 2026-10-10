import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqflite;

import 'package:zuno/core/matrix/shared_database_open.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('com.davidmartos96.sqflite_sqlcipher');
  final plaintextHeader = ascii.encode('SQLite format 3\u0000');

  late String path;
  late List<String> events;
  late List<Map<Object?, Object?>> opens;
  late List<Duration> waits;
  late int busyOpens;
  late void Function()? onKeylessOpen;
  late bool keylessOpenIsFresh;
  late Object keyedTables;

  List<int> encryptedBytes() {
    final random = Random(7);
    return List<int>.generate(4096, (_) => random.nextInt(256));
  }

  setUp(() {
    final directory = Directory.systemTemp.createTempSync('zuno_shared_db');
    addTearDown(() => directory.deleteSync(recursive: true));
    path = '${directory.path}/zuno.db';
    events = [];
    opens = [];
    waits = [];
    busyOpens = 0;
    onKeylessOpen = null;
    keylessOpenIsFresh = false;
    keyedTables = 20;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments is Map ? call.arguments as Map : const {};
      switch (call.method) {
        case 'openDatabase':
          opens.add(args);
          final keyed = args.containsKey('password');
          events.add(keyed ? 'open with key' : 'open without key');
          if (!keyed) onKeylessOpen?.call();
          if (!keyed && keylessOpenIsFresh) return {'id': 2};
          return {
            'id': 1,
            'recovered': true,
            if (opens.length <= busyOpens) 'recoveredInTransaction': true,
          };
        case 'execute':
          events.add('${args['sql']}');
          return null;
        case 'query':
          events.add('probe');
          final tables = keyedTables;
          if (tables is! int) {
            throw PlatformException(code: 'sqlite_error', message: '$tables');
          }
          return {
            'columns': ['tables'],
            'rows': [
              [tables],
            ],
          };
        case 'closeDatabase':
          events.add('close');
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

  Future<sqflite.Database> open() => openSharedDatabase(
    path,
    password: 'the-key',
    wait: (delay) async {
      waits.add(delay);
      events.add('wait');
    },
  );

  void abandonedTransactionOnAnEncryptedDatabase() {
    busyOpens = 1 << 30;
    File(path).writeAsBytesSync(encryptedBytes());
  }

  test(
    'opens with the key straight away when no transaction is open',
    () async {
      final database = await open();

      expect(database.isOpen, isTrue);
      expect(opens.single['password'], 'the-key');
      expect(waits, isEmpty);
      expect(events, ['open with key']);
    },
  );

  test('waits for another isolate to finish its transaction, then opens with '
      'the key and leaves that transaction alone', () async {
    busyOpens = 3;

    final database = await open();

    expect(database.isOpen, isTrue);
    expect(opens, hasLength(4));
    expect(opens.map((args) => args['password']), everyElement('the-key'));
    expect(waits, hasLength(3));
    expect(events, isNot(contains('ROLLBACK')));
  });

  test('retries quickly, and gives an open transaction the whole wait budget '
      'before treating it as abandoned', () async {
    abandonedTransactionOnAnEncryptedDatabase();

    await open();

    expect(waits.first, lessThanOrEqualTo(const Duration(milliseconds: 10)));
    expect(
      waits.fold(Duration.zero, (total, delay) => total + delay),
      greaterThanOrEqualTo(sharedDatabaseWaitBudget),
    );
  });

  test('rolls back a transaction no isolate ever finishes, reopening the '
      'shared connection without the key only once the wait runs out, and '
      'only keeps it once it reads the keyed tables', () async {
    abandonedTransactionOnAnEncryptedDatabase();

    final database = await open();

    expect(database.isOpen, isTrue);
    expect(events.where((event) => event == 'ROLLBACK'), hasLength(1));
    expect(events.sublist(events.length - 4), [
      'open with key',
      'open without key',
      'ROLLBACK',
      'probe',
    ]);
    expect(
      opens.take(opens.length - 1).map((args) => args['password']),
      everyElement('the-key'),
    );
    expect(events, isNot(contains('close')));
  });

  for (final (label, bytes) in [
    ('no database file', null),
    ('a plaintext database file', [...plaintextHeader, 1, 2, 3]),
    ('a file too short to hold a header', [1, 2, 3]),
  ]) {
    test('never opens without the key when there is $label', () async {
      busyOpens = 1 << 30;
      if (bytes != null) File(path).writeAsBytesSync(bytes);

      await expectLater(open(), throwsA(isA<StateError>()));

      expect(events, isNot(contains('open without key')));
      expect(events, isNot(contains('ROLLBACK')));
      expect(events.where((event) => event.startsWith('delete')), isEmpty);
    });
  }

  test('removes and refuses a database that the keyless reopen left '
      'unencrypted', () async {
    abandonedTransactionOnAnEncryptedDatabase();
    keylessOpenIsFresh = true;
    onKeylessOpen = () =>
        File(path).writeAsBytesSync([...plaintextHeader, 0, 0, 0, 0]);

    await expectLater(open(), throwsA(isA<StateError>()));

    expect(events, contains('delete $path'));
    expect(events, isNot(contains('ROLLBACK')));
  });

  test('fails closed without deleting or closing anything when the file '
      'cannot be read back but the reopened connection is the keyed '
      'one', () async {
    abandonedTransactionOnAnEncryptedDatabase();
    onKeylessOpen = () => File(path).deleteSync();

    await expectLater(open(), throwsA(isA<StateError>()));

    expect(events, contains('probe'));
    expect(events.where((event) => event.startsWith('delete')), isEmpty);
    expect(events, isNot(contains('close')));
  });

  test('closes, but never deletes, a keyless reopen whose file cannot be '
      'read back and whose connection is not the keyed one', () async {
    abandonedTransactionOnAnEncryptedDatabase();
    keylessOpenIsFresh = true;
    keyedTables = 0;
    onKeylessOpen = () => File(path).writeAsBytesSync([]);

    await expectLater(open(), throwsA(isA<StateError>()));

    expect(events, contains('close'));
    expect(events.where((event) => event.startsWith('delete')), isEmpty);
  });

  for (final (label, answer) in [
    ('sees none of the keyed tables', 0 as Object),
    ('cannot read the schema at all', 'file is not a database'),
  ]) {
    test('closes, but never deletes, a keyless reopen that $label', () async {
      abandonedTransactionOnAnEncryptedDatabase();
      keylessOpenIsFresh = true;
      keyedTables = answer;

      await expectLater(open(), throwsA(isA<StateError>()));

      expect(events, contains('close'));
      expect(events.where((event) => event.startsWith('delete')), isEmpty);
    });
  }

  test('does not retry a failure that is not another isolate\'s '
      'transaction', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'openDatabase') return null;
      opens.add(call.arguments as Map);
      throw PlatformException(code: 'sqlite_error', message: 'open_failed');
    });

    await expectLater(open(), throwsA(isA<sqflite.DatabaseException>()));

    expect(opens, hasLength(1));
    expect(waits, isEmpty);
  });
}
