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
  for (final list in List.of(client.userDeviceKeys.values)) {
    if (list.userId == ownId) continue;
    final master = list.masterKey;
    if (master == null || !master.directVerified) continue;
    try {
      await master.setVerified(false, false);
    } catch (_) {}
  }
}
