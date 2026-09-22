import 'package:matrix/matrix.dart';

Future<void> forceSyncNow(Client client) async {
  try {
    await client.abortSync();
    await client.oneShotSync(timeout: Duration.zero);
  } finally {
    client.backgroundSync = true;
  }
}
