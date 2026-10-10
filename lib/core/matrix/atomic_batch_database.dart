import 'package:sqflite_sqlcipher/sqlite_api.dart';

import '../errors/caught_errors.dart';

class AtomicBatchDatabase implements Database {
  AtomicBatchDatabase(this._database);

  final Database _database;
  Future<void> _tail = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  @override
  String get path => _database.path;

  @override
  bool get isOpen => _database.isOpen;

  @override
  Database get database => this;

  @override
  Future<void> close() => _serialized(_database.close);

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) =>
      _serialized(() => _database.execute(sql, arguments));

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) =>
      _serialized(() => _database.rawInsert(sql, arguments));

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) => _serialized(
    () => _database.insert(
      table,
      values,
      nullColumnHack: nullColumnHack,
      conflictAlgorithm: conflictAlgorithm,
    ),
  );

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) => _serialized(
    () => _database.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    ),
  );

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) => _serialized(() => _database.rawQuery(sql, arguments));

  @override
  Future<QueryCursor> rawQueryCursor(
    String sql,
    List<Object?>? arguments, {
    int? bufferSize,
  }) => _serialized(
    () => _database.rawQueryCursor(sql, arguments, bufferSize: bufferSize),
  );

  @override
  Future<QueryCursor> queryCursor(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
    int? bufferSize,
  }) => _serialized(
    () => _database.queryCursor(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
      bufferSize: bufferSize,
    ),
  );

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) =>
      _serialized(() => _database.rawUpdate(sql, arguments));

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) => _serialized(
    () => _database.update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
      conflictAlgorithm: conflictAlgorithm,
    ),
  );

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) =>
      _serialized(() => _database.rawDelete(sql, arguments));

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) =>
      _serialized(
        () => _database.delete(table, where: where, whereArgs: whereArgs),
      );

  @override
  Batch batch() => _AtomicBatch(this);

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) => _serialized(() => _database.transaction(action, exclusive: exclusive));

  @override
  Future<T> readTransaction<T>(Future<T> Function(Transaction txn) action) =>
      _serialized(() => _database.readTransaction(action));

  @override
  Future<T> devInvokeMethod<T>(String method, [Object? arguments]) =>
      throw UnsupportedError('devInvokeMethod is for sqflite development');

  @override
  Future<T> devInvokeSqlMethod<T>(
    String method,
    String sql, [
    List<Object?>? arguments,
  ]) => throw UnsupportedError('devInvokeSqlMethod is for sqflite development');
}

bool _nothingToRollBack(Object error) =>
    error is DatabaseException &&
    '$error'.contains('cannot rollback - no transaction is active');

class _AtomicBatch implements Batch {
  _AtomicBatch(this._owner);

  final AtomicBatchDatabase _owner;
  final _operations = <void Function(Batch batch)>[];

  Batch _replay({String? begin}) {
    final batch = _owner._database.batch();
    if (begin != null) batch.execute(begin);
    for (final operation in _operations) {
      operation(batch);
    }
    if (begin != null) batch.execute('COMMIT');
    return batch;
  }

  @override
  Future<List<Object?>> commit({
    bool? exclusive,
    bool? noResult,
    bool? continueOnError,
  }) async {
    if (continueOnError == true) {
      throw UnsupportedError('continueOnError would commit a partial batch');
    }
    if (_operations.isEmpty) return const [];
    final batch = _replay(
      begin: exclusive == true ? 'BEGIN EXCLUSIVE' : 'BEGIN IMMEDIATE',
    );
    return _owner._serialized(() async {
      try {
        final results = await batch.apply(noResult: noResult);
        return noResult == true
            ? results
            : results.sublist(1, results.length - 1);
      } catch (_) {
        try {
          await _owner._database.execute('ROLLBACK');
        } catch (e, s) {
          if (!_nothingToRollBack(e)) {
            reportCaught('roll back a failed batch', e, s);
          }
        }
        rethrow;
      }
    });
  }

  @override
  Future<List<Object?>> apply({bool? noResult, bool? continueOnError}) =>
      _owner._serialized(
        () => _replay().apply(
          noResult: noResult,
          continueOnError: continueOnError,
        ),
      );

  @override
  int get length => _operations.length;

  @override
  void rawInsert(String sql, [List<Object?>? arguments]) =>
      _operations.add((batch) => batch.rawInsert(sql, arguments));

  @override
  void insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) => _operations.add(
    (batch) => batch.insert(
      table,
      values,
      nullColumnHack: nullColumnHack,
      conflictAlgorithm: conflictAlgorithm,
    ),
  );

  @override
  void rawUpdate(String sql, [List<Object?>? arguments]) =>
      _operations.add((batch) => batch.rawUpdate(sql, arguments));

  @override
  void update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) => _operations.add(
    (batch) => batch.update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
      conflictAlgorithm: conflictAlgorithm,
    ),
  );

  @override
  void rawDelete(String sql, [List<Object?>? arguments]) =>
      _operations.add((batch) => batch.rawDelete(sql, arguments));

  @override
  void delete(String table, {String? where, List<Object?>? whereArgs}) =>
      _operations.add(
        (batch) => batch.delete(table, where: where, whereArgs: whereArgs),
      );

  @override
  void execute(String sql, [List<Object?>? arguments]) =>
      _operations.add((batch) => batch.execute(sql, arguments));

  @override
  void query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) => _operations.add(
    (batch) => batch.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    ),
  );

  @override
  void rawQuery(String sql, [List<Object?>? arguments]) =>
      _operations.add((batch) => batch.rawQuery(sql, arguments));
}
