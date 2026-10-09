import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' show Database;

import 'package:zuno/core/matrix/database_compaction.dart';
import 'package:zuno/core/matrix/ephemeral_to_device.dart';
import 'package:zuno/core/push/read_model/session_exporter.dart';

typedef _Statement = (String method, String sql);

class _RecordingDatabase implements Database {
  _RecordingDatabase({
    required this.autoVacuum,
    this.pageCount = 0,
    this.freelistCount = 0,
  });

  final int autoVacuum;
  final int pageCount;
  final int freelistCount;
  final statements = <_Statement>[];
  String? failing;
  var closed = false;

  @override
  bool get isOpen => !closed;

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    statements.add(('rawQuery', sql));
    if (sql == failing) throw StateError('disk full');
    final value = switch (sql) {
      'PRAGMA auto_vacuum' => autoVacuum,
      'PRAGMA page_count' => pageCount,
      'PRAGMA freelist_count' => freelistCount,
      _ => null,
    };
    return [
      if (value != null) {'value': value},
    ];
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    if (sql.startsWith('PRAGMA') && !sql.contains('=')) {
      throw StateError(
        'Queries can be performed using SQLiteDatabase query or rawQuery '
        'methods only.',
      );
    }
    statements.add(('execute', sql));
    if (sql == failing) throw StateError('disk full');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ClearingDatabase extends MatrixSdkDatabase {
  _ClearingDatabase(this.sqlite)
    : super.buildWithoutOpen('test', database: sqlite);

  final _RecordingDatabase sqlite;
  Object? clearFailure;

  @override
  Future<void> clearCache() async {
    sqlite.statements.add(_clear);
    if (clearFailure case final failure?) throw failure;
  }
}

class _CompactingDatabase extends _ClearingDatabase
    with CompactsAfterCacheClear {
  _CompactingDatabase(super.sqlite);
}

class _NoSessionEvents implements InboundSessionEvents {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _clear = ('super', 'clearCache');
const _switchOver = [
  ('execute', 'PRAGMA auto_vacuum = 2'),
  ('execute', 'VACUUM'),
];
const _measure = [
  ('rawQuery', 'PRAGMA auto_vacuum'),
  ('rawQuery', 'PRAGMA page_count'),
  ('rawQuery', 'PRAGMA freelist_count'),
];

void main() {
  group('each open', () {
    test('a database that already gives space back frees a bounded share of '
        'its free pages, reading each freed page back as a row', () async {
      final database = _RecordingDatabase(autoVacuum: 2);

      await compactOnOpen(database);

      expect(database.statements, [
        ('rawQuery', 'PRAGMA auto_vacuum'),
        ('rawQuery', 'PRAGMA incremental_vacuum(1000)'),
      ]);
    });

    test('a fresh database is switched over in one rewrite', () async {
      final database = _RecordingDatabase(autoVacuum: 0);

      await compactOnOpen(database);

      expect(database.statements, [..._measure, ..._switchOver]);
    });

    test('a large database that cannot give space back yet waits for the '
        'next cache clear instead of a rewrite at startup', () async {
      final database = _RecordingDatabase(autoVacuum: 0, pageCount: 100000);

      await compactOnOpen(database);

      expect(database.statements, _measure);
    });

    test('a large file that is mostly free pages is switched over, since a '
        'rewrite costs only what it keeps', () async {
      final database = _RecordingDatabase(
        autoVacuum: 0,
        pageCount: 100000,
        freelistCount: 99900,
      );

      await compactOnOpen(database);

      expect(database.statements, [..._measure, ..._switchOver]);
    });

    test('a step that fails stops there and leaves the caller to log '
        'it', () async {
      final database = _RecordingDatabase(autoVacuum: 0)
        ..failing = 'PRAGMA page_count';

      await expectLater(compactOnOpen(database), throwsStateError);

      expect(database.statements.last, ('rawQuery', 'PRAGMA page_count'));
    });
  });

  group('after a cache clear', () {
    test('a clear made below any client, as a migration makes it, is given '
        'back in one switching rewrite', () async {
      final database = _CompactingDatabase(_RecordingDatabase(autoVacuum: 0));

      await database.clearCache();

      expect(database.sqlite.statements, [_clear, ..._switchOver]);
    });

    test('the clear still succeeds when the rewrite fails', () async {
      final database = _CompactingDatabase(_RecordingDatabase(autoVacuum: 2))
        ..sqlite.failing = 'VACUUM';

      await database.clearCache();

      expect(database.sqlite.statements, [_clear, ..._switchOver]);
    });

    test('a closed database is cleared but never rewritten', () async {
      final database = _CompactingDatabase(_RecordingDatabase(autoVacuum: 2))
        ..sqlite.closed = true;

      await database.clearCache();

      expect(database.sqlite.statements, [_clear]);
    });

    test('a clear that fails is never rewritten and still says so', () async {
      final database = _CompactingDatabase(_RecordingDatabase(autoVacuum: 2))
        ..clearFailure = StateError('database locked');

      await expectLater(database.clearCache(), throwsStateError);

      expect(database.sqlite.statements, [_clear]);
    });

    test('both app databases give space back after every clear', () {
      final sqlite = _RecordingDatabase(autoVacuum: 2);

      expect(
        ZunoDatabase('zuno', database: sqlite),
        isA<CompactsAfterCacheClear>(),
      );
      expect(
        SessionExportingDatabase(
          'zuno',
          database: sqlite,
          inboundSessionEvents: _NoSessionEvents(),
        ),
        isA<CompactsAfterCacheClear>(),
      );
    });
  });
}
