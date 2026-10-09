import 'package:matrix/matrix.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' show Database;

import '../errors/best_effort.dart';

const _incrementalAutoVacuum = 2;

Future<void> compactDatabase(Database database) async {
  final mode = (await database.rawQuery('PRAGMA auto_vacuum'))
      .firstOrNull
      ?.values
      .firstOrNull;
  if (mode != _incrementalAutoVacuum) {
    await database.execute('PRAGMA auto_vacuum = $_incrementalAutoVacuum');
    await database.execute('VACUUM');
    return;
  }
  await database.execute('PRAGMA incremental_vacuum');
}

Database? liveDatabase(Client client) => switch (client.database) {
  final MatrixSdkDatabase database => database.database,
  _ => null,
};

Future<void> clearCacheAndCompact(Client client) async {
  await client.clearCache();
  final database = liveDatabase(client);
  if (database == null) return;
  await runBestEffort(
    () => compactDatabase(database),
    label: 'compact the database after clearing the cache',
  );
}
