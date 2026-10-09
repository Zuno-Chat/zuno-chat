import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' show Database;

import 'package:zuno/core/matrix/database_compaction.dart';

class _RecordingDatabase implements Database {
  _RecordingDatabase({required this.autoVacuum});

  final int autoVacuum;
  final statements = <String>[];
  String? failing;

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    statements.add(sql);
    return [
      {'auto_vacuum': autoVacuum},
    ];
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    if (const {
      'PRAGMA auto_vacuum',
      'PRAGMA incremental_vacuum',
    }.contains(sql)) {
      throw StateError(
        'Queries can be performed using SQLiteDatabase query or rawQuery '
        'methods only.',
      );
    }
    statements.add(sql);
    if (sql == failing) throw StateError('disk full');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ClearingClient extends Client {
  _ClearingClient(_RecordingDatabase sqlite)
    : super(
        'test',
        database: MatrixSdkDatabase.buildWithoutOpen('test', database: sqlite),
      );

  var clears = 0;
  Object? clearFailure;

  @override
  Future<void> clearCache() async {
    clears++;
    if (clearFailure case final failure?) throw failure;
  }
}

void main() {
  group('compacting', () {
    test('a database that cannot give space back is switched over in one '
        'rewrite', () async {
      final database = _RecordingDatabase(autoVacuum: 0);

      await compactDatabase(database);

      expect(database.statements, [
        'PRAGMA auto_vacuum',
        'PRAGMA auto_vacuum = 2',
        'VACUUM',
      ]);
    });

    test('a database already switched gives back its free pages', () async {
      final database = _RecordingDatabase(autoVacuum: 2);

      await compactDatabase(database);

      expect(database.statements, [
        'PRAGMA auto_vacuum',
        'PRAGMA incremental_vacuum',
      ]);
    });
  });

  group('clearing the cache', () {
    test('gives the freed space back', () async {
      final database = _RecordingDatabase(autoVacuum: 2);
      final client = _ClearingClient(database);

      await clearCacheAndCompact(client);

      expect(client.clears, 1);
      expect(database.statements, contains('PRAGMA incremental_vacuum'));
    });

    test('still counts as done when giving space back fails', () async {
      final database = _RecordingDatabase(autoVacuum: 2)
        ..failing = 'PRAGMA incremental_vacuum';
      final client = _ClearingClient(database);

      await clearCacheAndCompact(client);

      expect(client.clears, 1);
    });

    test('that fails touches nothing else and says so', () async {
      final database = _RecordingDatabase(autoVacuum: 2);
      final client = _ClearingClient(database)
        ..clearFailure = StateError('database locked');

      await expectLater(clearCacheAndCompact(client), throwsStateError);

      expect(database.statements, isEmpty);
    });
  });
}
