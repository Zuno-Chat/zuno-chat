import 'package:matrix/matrix.dart';

import '../errors/best_effort.dart';

Future<bool> restoreKeyBackupFromRecovery(Client client) async {
  final keyManager = client.encryption?.keyManager;
  if (keyManager == null) return false;
  return runBestEffort(keyManager.loadAllKeys, label: 'loadAllKeys');
}
