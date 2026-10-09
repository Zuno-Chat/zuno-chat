import 'package:matrix/matrix.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' show Database, Sqflite;

import '../errors/best_effort.dart';

const _incrementalAutoVacuum = 2;
const _pagesPerOpen = 1000;

Future<void> compactOnOpen(Database database) async {
  if (await _pragma(database, 'auto_vacuum') == _incrementalAutoVacuum) {
    await database.rawQuery('PRAGMA incremental_vacuum($_pagesPerOpen)');
    return;
  }
  final pages = await _pragma(database, 'page_count');
  final free = await _pragma(database, 'freelist_count');
  if (pages - free <= _pagesPerOpen) await _vacuum(database);
}

mixin CompactsAfterCacheClear on MatrixSdkDatabase {
  @override
  Future<void> clearCache() async {
    await super.clearCache();
    final database = this.database;
    if (database == null || !database.isOpen) return;
    await runBestEffort(
      () => _vacuum(database),
      label: 'compact the database after clearing the cache',
    );
  }
}

Database? liveDatabase(Client client) => switch (client.database) {
  final MatrixSdkDatabase database => database.database,
  _ => null,
};

Future<int> _pragma(Database database, String name) async =>
    Sqflite.firstIntValue(await database.rawQuery('PRAGMA $name')) ?? 0;

Future<void> _vacuum(Database database) async {
  await database.execute('PRAGMA auto_vacuum = $_incrementalAutoVacuum');
  await database.execute('VACUUM');
}
