import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../errors/best_effort.dart';
import 'database_compaction.dart';

const leftRoomsRepairedKey = 'store.left_rooms_repaired';

Future<void> repairLeftRoomsOnce(Client client, SharedPreferences prefs) async {
  if (prefs.getBool(leftRoomsRepairedKey) ?? false) return;
  if (client.isLogged()) {
    final rebuilt = await runBestEffort(
      () => clearCacheAndCompact(client),
      label: 'rebuild the store to drop rooms left before the SDK fix',
    );
    if (!rebuilt) return;
  }
  await prefs.setBool(leftRoomsRepairedKey, true);
}
