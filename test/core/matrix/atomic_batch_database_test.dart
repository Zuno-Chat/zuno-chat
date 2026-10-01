import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqflite;

import 'package:zuno/core/matrix/atomic_batch_database.dart';

const _channel = MethodChannel('com.davidmartos96.sqflite_sqlcipher');

const _begin = {
  'method': 'execute',
  'sql': 'BEGIN IMMEDIATE',
  'inTransaction': true,
};

const _commit = {'method': 'execute', 'sql': 'COMMIT', 'inTransaction': false};

class _Call {
  _Call(this.method, this.arguments);

  final String method;
  final Map<Object?, Object?> arguments;

  String get label =>
      method == 'execute' ? 'execute ${arguments['sql']}' : method;

  List<Map<Object?, Object?>> get operations =>
      (arguments['operations'] as List).cast<Map<Object?, Object?>>();
}

class _Native {
  final calls = <_Call>[];
  Future<Object?> Function(_Call call)? onBatch;
  Future<Object?> Function(_Call call)? onExecute;
  Future<void> Function(_Call call)? onQuery;

  Future<Object?> handle(MethodCall methodCall) async {
    final call = _Call(
      methodCall.method,
      (methodCall.arguments as Map?)?.cast<Object?, Object?>() ?? const {},
    );
    if (call.method == 'openDatabase') return 1;
    calls.add(call);
    switch (call.method) {
      case 'batch':
        final onBatch = this.onBatch;
        if (onBatch != null) return onBatch(call);
        return call.arguments['noResult'] == true
            ? null
            : [
                for (final _ in call.operations) {'result': null},
              ];
      case 'execute':
        final onExecute = this.onExecute;
        if (onExecute != null) return onExecute(call);
        return null;
      case 'query':
        await onQuery?.call(call);
        return {'columns': <String>[], 'rows': <List<Object?>>[]};
      case 'insert' || 'update':
        return 1;
      default:
        return null;
    }
  }
}

class _SharedConnection {
  final committed = <String, Object?>{};
  final _levels = <bool>[];
  Map<String, Object?>? _pending;
  final _destroyedIds = <Object?>{};
  Object? _destroyAfterNextCall;
  final _destroyed = Completer<void>();
  Future<void> _thread = Future<void>.value();
  var _lastOpenedId = 0;

  int get openDepth => _levels.length;

  int get lastOpenedId => _lastOpenedId;

  Future<void> get destroyed => _destroyed.future;

  void destroyAfterNextCallFrom(int id) => _destroyAfterNextCall = id;

  Future<Object?> handle(MethodCall call) {
    final arguments =
        (call.arguments as Map?)?.cast<Object?, Object?>() ?? const {};
    final id = arguments['id'];
    if (_destroyedIds.contains(id)) return Completer<Object?>().future;
    final reply = _thread.then((_) async {
      await Future<void>.delayed(Duration.zero);
      try {
        return _run(call.method, arguments);
      } finally {
        if (id != null && id == _destroyAfterNextCall) {
          _destroyedIds.add(id);
          _destroyAfterNextCall = null;
          _destroyed.complete();
        }
      }
    });
    _thread = reply.then<void>((_) {}, onError: (_) {});
    return reply;
  }

  Object? _run(String method, Map<Object?, Object?> arguments) {
    switch (method) {
      case 'openDatabase':
        return ++_lastOpenedId;
      case 'execute':
        _execute(arguments['sql']! as String, arguments['arguments'] as List?);
        return null;
      case 'insert' || 'update':
        _execute(arguments['sql']! as String, arguments['arguments'] as List?);
        return 1;
      case 'batch':
        final operations = (arguments['operations'] as List)
            .cast<Map<Object?, Object?>>();
        for (final operation in operations) {
          _execute(
            operation['sql']! as String,
            operation['arguments'] as List?,
          );
        }
        return arguments['noResult'] == true
            ? null
            : [
                for (final _ in operations) {'result': null},
              ];
      case 'query':
        return {'columns': <String>[], 'rows': <List<Object?>>[]};
      default:
        return null;
    }
  }

  void _execute(String sql, List<Object?>? values) {
    final statement = sql.trimLeft().toUpperCase();
    if (statement.startsWith('BEGIN')) {
      if (_levels.isEmpty) _pending = {};
      _levels.add(false);
    } else if (statement.startsWith('COMMIT')) {
      final childFailed = _levels.removeLast();
      if (_levels.isNotEmpty) {
        if (childFailed) _levels[_levels.length - 1] = true;
      } else {
        if (!childFailed) committed.addAll(_pending!);
        _pending = null;
      }
    } else if (statement.startsWith('ROLLBACK')) {
      _levels.removeLast();
      if (_levels.isNotEmpty) {
        _levels[_levels.length - 1] = true;
      } else {
        _pending = null;
      }
    } else if (statement.startsWith('INSERT')) {
      final table = RegExp(r'INTO (\w+)').firstMatch(sql)!.group(1);
      _write('$table/${values![0]}', values[1]);
    } else if (statement.startsWith('DELETE')) {
      final table = RegExp(r'FROM (\w+)').firstMatch(sql)!.group(1);
      _write('$table/${values?.first}', null);
    }
  }

  void _write(String key, Object? value) {
    if (_levels.isEmpty) {
      committed[key] = value;
    } else {
      _pending![key] = value;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late _Native native;

  setUp(() {
    native = _Native();
    messenger.setMockMethodCallHandler(_channel, native.handle);
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
  });

  Future<sqflite.Database> openRaw() => sqflite.openDatabase(
    '/zuno/zuno.db',
    password: 'the-key',
    singleInstance: false,
  );

  Future<AtomicBatchDatabase> open() async =>
      AtomicBatchDatabase(await openRaw());

  PlatformException diskFull() => PlatformException(
    code: 'sqlite_error',
    message: 'database or disk is full',
  );

  Matcher failsWith(String message) => throwsA(
    isA<sqflite.DatabaseException>().having(
      (e) => e.toString(),
      'error',
      contains(message),
    ),
  );

  Iterable<String> labels() => native.calls.map((call) => call.label);

  group('a batch commit', () {
    test(
      'reaches native as one batch that begins and commits itself',
      () async {
        final database = await open();

        final batch = database.batch()
          ..insert('box', {'k': 'a', 'v': '1'})
          ..delete('box', where: 'k = ?', whereArgs: ['b']);
        await batch.commit(noResult: true);

        expect(labels(), ['batch']);
        final operations = native.calls.single.operations;
        expect(operations.first, _begin);
        expect(operations.map((operation) => operation['method']), [
          'execute',
          'insert',
          'update',
          'execute',
        ]);
        expect(operations.last, _commit);
      },
    );

    test('carries a whole SDK transaction in that one call', () async {
      final sdk = await MatrixSdkDatabase.init('zuno', database: await open());
      native.calls.clear();

      await sdk.insertClient(
        'zuno',
        'https://example.org',
        'token',
        null,
        null,
        '@me:example.org',
        'DEVICE',
        'Phone',
        'prev-batch',
        'olm-account',
        null,
      );

      expect(labels(), ['batch']);
      final operations = native.calls.single.operations;
      expect(operations.first, _begin);
      expect(operations.last, _commit);
      expect(
        operations
            .sublist(1, operations.length - 1)
            .map((operation) => operation['sql']),
        everyElement(anyOf(startsWith('INSERT'), startsWith('DELETE'))),
      );
    });

    test('that fails is rolled back once, and its error surfaces', () async {
      final database = await open();
      native.onBatch = (_) async => throw diskFull();

      final batch = database.batch()..insert('box', {'k': 'a', 'v': '1'});

      await expectLater(
        batch.commit(noResult: true),
        failsWith('disk is full'),
      );
      expect(labels(), ['batch', 'execute ROLLBACK']);
    });

    test('whose ROLLBACK fails still surfaces the batch error', () async {
      final database = await open();
      native.onBatch = (_) async => throw diskFull();
      native.onExecute = (_) async => throw PlatformException(
        code: 'sqlite_error',
        message: 'no current transaction',
      );

      final batch = database.batch()..insert('box', {'k': 'a', 'v': '1'});

      await expectLater(
        batch.commit(noResult: true),
        failsWith('disk is full'),
      );
      expect(labels(), ['batch', 'execute ROLLBACK']);
    });

    test('that fails is rolled back before any other call from this isolate '
        'reaches native', () async {
      final database = await open();
      final batchArrived = Completer<void>();
      final release = Completer<void>();
      native.onBatch = (_) async {
        batchArrived.complete();
        await release.future;
        throw diskFull();
      };

      final batch = database.batch()..insert('box', {'k': 'a', 'v': '1'});
      final commit = batch.commit(noResult: true);
      await batchArrived.future;
      final write = database.insert('box', {'k': 'b', 'v': '2'});
      await pumpEventQueue();

      expect(labels(), ['batch']);

      release.complete();
      await expectLater(commit, failsWith('disk is full'));
      await write;

      expect(labels(), ['batch', 'execute ROLLBACK', 'insert']);
    });

    test('with nothing in it makes no native call', () async {
      final database = await open();

      expect(await database.batch().commit(noResult: true), isEmpty);
      expect(native.calls, isEmpty);
    });

    test('that may continue past a failed write is refused', () async {
      final database = await open();
      final batch = database.batch()..insert('box', {'k': 'a', 'v': '1'});

      await expectLater(
        batch.commit(continueOnError: true),
        throwsUnsupportedError,
      );
      expect(native.calls, isEmpty);
    });

    test('returns the results of its own writes only', () async {
      final database = await open();
      native.onBatch = (_) async => [
        {'result': null},
        {'result': 7},
        {'result': 1},
        {'result': null},
      ];

      final batch = database.batch()
        ..insert('box', {'k': 'a', 'v': '1'})
        ..delete('box', where: 'k = ?', whereArgs: ['b']);

      expect(await batch.commit(), [7, 1]);
    });

    test('asked to be exclusive begins EXCLUSIVE', () async {
      final database = await open();
      final batch = database.batch()..insert('box', {'k': 'a', 'v': '1'});

      await batch.commit(exclusive: true, noResult: true);

      expect(native.calls.single.operations.first, {
        'method': 'execute',
        'sql': 'BEGIN EXCLUSIVE',
        'inTransaction': true,
      });
    });
  });

  test('a batch apply sends its writes as they are, without BEGIN or '
      'COMMIT', () async {
    final database = await open();
    final batch = database.batch()
      ..insert('box', {'k': 'a', 'v': '1'})
      ..delete('box', where: 'k = ?', whereArgs: ['b']);

    await batch.apply(noResult: true);

    expect(labels(), ['batch']);
    expect(
      native.calls.single.operations.map((operation) => operation['method']),
      ['insert', 'update'],
    );
  });

  test('reads and single writes go straight through', () async {
    final raw = await openRaw();
    final database = AtomicBatchDatabase(raw);

    await database.query(
      'box',
      columns: ['v'],
      where: 'k = ?',
      whereArgs: ['a'],
    );
    await database.insert('box', {
      'k': 'a',
      'v': '1',
    }, conflictAlgorithm: sqflite.ConflictAlgorithm.replace);
    await database.execute('VACUUM');

    expect(labels(), ['query', 'insert', 'execute VACUUM']);
    expect(
      native.calls[1].arguments['sql'],
      'INSERT OR REPLACE INTO box (k, v) VALUES (?, ?)',
    );
    expect(database.path, raw.path);
    expect(database.database, same(database));
  });

  group('reads', () {
    late Completer<void> releaseReads;

    setUp(() {
      releaseReads = Completer<void>();
      native.onQuery = (_) => releaseReads.future;
    });

    test('issued together already reach native one at a time without the '
        'wrapper, so it costs them no extra waiting', () async {
      final raw = await openRaw();

      final reads = [
        raw.rawQuery('SELECT * FROM box_rooms'),
        raw.query('box_account_data'),
        raw.rawQuery('SELECT * FROM box_user_device_keys'),
      ];
      await pumpEventQueue();

      expect(labels(), ['query']);
      releaseReads.complete();
      await Future.wait(reads);
      expect(labels(), ['query', 'query', 'query']);
    });

    test('wait for a batch already in flight, and for its rollback', () async {
      releaseReads.complete();
      final database = await open();
      final release = Completer<void>();
      native.onBatch = (_) async {
        await release.future;
        throw diskFull();
      };

      final commit = (database.batch()..insert('box', {'k': 'a', 'v': '1'}))
          .commit(noResult: true);
      final read = database.rawQuery('SELECT * FROM box');
      await pumpEventQueue();

      expect(labels(), ['batch']);

      release.complete();
      await expectLater(commit, failsWith('disk is full'));
      await read;

      expect(labels(), ['batch', 'execute ROLLBACK', 'query']);
    });

    test('in flight hold back a later write until they finish', () async {
      final database = await open();

      final read = database.rawQuery('SELECT * FROM box');
      final write = database.insert('box', {'k': 'a', 'v': '1'});
      await pumpEventQueue();

      expect(labels(), ['query']);

      releaseReads.complete();
      await read;
      await write;

      expect(labels(), ['query', 'insert']);
    });

    test('never overtake a write that is still waiting its turn', () async {
      releaseReads.complete();
      final database = await open();
      final release = Completer<void>();
      native.onBatch = (_) async {
        await release.future;
        return null;
      };

      final commit = (database.batch()..insert('box', {'k': 'a', 'v': '1'}))
          .commit(noResult: true);
      final write = database.insert('box', {'k': 'b', 'v': '2'});
      final read = database.rawQuery('SELECT * FROM box');
      await pumpEventQueue();

      expect(labels(), ['batch']);

      release.complete();
      await commit;
      await write;
      await read;

      expect(labels(), ['batch', 'insert', 'query']);
    });
  });

  group('two engines sharing one native connection', () {
    late _SharedConnection connection;

    setUp(() {
      connection = _SharedConnection();
      messenger.setMockMethodCallHandler(_channel, connection.handle);
    });

    Future<(MatrixSdkDatabase, int)> engine({required bool atomic}) async {
      final raw = await openRaw();
      final id = connection.lastOpenedId;
      final database = await MatrixSdkDatabase.init(
        'zuno',
        database: atomic ? AtomicBatchDatabase(raw) : raw,
      );
      return (database, id);
    }

    Future<void> destroyOneMidTransactionThenWriteFromTheOther({
      required bool atomic,
    }) async {
      final (first, _) = await engine(atomic: atomic);
      final (second, secondId) = await engine(atomic: atomic);
      connection.destroyAfterNextCallFrom(secondId);
      unawaited(
        second.transaction(() async {
          await second.storeAccountData('im.zuno.second', {'n': 1});
        }),
      );
      await connection.destroyed;

      await first.transaction(() async {
        await first.storeAccountData('im.zuno.first', {'n': 2});
      });
      await first.storeAccountData('im.zuno.direct', {'n': 3});
    }

    test('an engine destroyed mid-transaction leaves nothing open, so the '
        "other engine's writes commit", () async {
      await destroyOneMidTransactionThenWriteFromTheOther(atomic: true);

      expect(connection.openDepth, 0);
      expect(connection.committed, contains('box_account_data/im.zuno.first'));
      expect(connection.committed, contains('box_account_data/im.zuno.direct'));
    });

    test('without the wrapper, the same death strands the other engine\'s '
        'writes in a transaction nobody will finish', () async {
      await destroyOneMidTransactionThenWriteFromTheOther(atomic: false);

      expect(connection.openDepth, 1);
      expect(
        connection.committed,
        isNot(contains('box_account_data/im.zuno.first')),
      );
      expect(
        connection.committed,
        isNot(contains('box_account_data/im.zuno.direct')),
      );
    });
  });
}
