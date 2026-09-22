import 'package:matrix/matrix.dart';

import 'confirmed_identity_store.dart';

Future<void> forgetConfirmationsAfterIdentityReset(
  Client client,
  ConfirmedIdentityStore store,
) async {
  try {
    await store.forgetAll();
  } catch (_) {}

  final ownId = client.userID;
  for (final entry in client.userDeviceKeys.entries) {
    if (entry.key == ownId) continue;
    final master = entry.value.masterKey;
    if (master == null || !master.directVerified) continue;
    try {
      await master.setVerified(false, false);
    } catch (_) {}
  }
}
